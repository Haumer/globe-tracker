require "net/http"
require "nokogiri"

class RssArticleHydrationService
  MAX_ATTEMPTS = 3
  FETCH_TIMEOUT = 8
  MAX_BODY_CHARS = 20_000

  class << self
    def enqueue_candidates(records, now: Time.current)
      article_ids = records.filter_map { |record| fetch(record, :news_article_id) }.uniq
      return 0 if article_ids.empty?

      claim_map = NewsClaim.where(news_article_id: article_ids, primary: true)
        .pluck(:news_article_id, :event_family, :event_type, :confidence)
        .each_with_object({}) do |(article_id, event_family, event_type, confidence), mapping|
          mapping[article_id] = {
            event_family: event_family,
            event_type: event_type,
            confidence: confidence,
          }
        end

      queued = 0
      NewsArticle.includes(:news_source).where(id: article_ids).find_each do |article|
        record = records.find { |entry| fetch(entry, :news_article_id) == article.id }
        decision = hydrate_decision(article, claim_map[article.id], record)
        next if decision[:priority] == :skip

        next unless mark_queued(article, decision[:reason], now)

        job = RssArticleHydrationJob.set(wait: hydration_delay_for(decision[:priority]))
        job.perform_later(article.id)
        queued += 1
      end

      queued
    end

    def hydrate(news_article_id)
      article = NewsArticle.find_by(id: news_article_id)
      return false unless article
      return false unless should_attempt_hydration?(article)

      mark_attempt_started(article)

      extracted = fetch_and_extract(article.url)
      if extracted.blank?
        mark_failure(article, "empty_extraction")
        return false
      end

      apply_hydration(article, extracted)
      true
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, OpenSSL::SSL::SSLError => e
      article&.then { |record| mark_failure(record, e.class.name.demodulize.underscore) }
      false
    rescue StandardError => e
      article&.then { |record| mark_failure(record, e.class.name.demodulize.underscore) }
      Rails.logger.warn("RssArticleHydrationService: #{e.message}")
      false
    end

    def hydrate_decision(article, claim_summary = nil, record = nil)
      return skip("not_rss") unless rss_article?(article)
      return skip("out_of_scope") if article.content_scope == "out_of_scope"
      return skip("too_old") if stale_article?(article)
      return skip("blocked_domain") if blocked_domain?(article.publisher_domain)
      return skip("too_many_attempts") if article.hydration_attempts.to_i >= MAX_ATTEMPTS
      return skip("already_hydrated") if article.hydration_status == "hydrated"

      if article.content_scope == "core"
        return decision(:immediate, "core_scope")
      end

      if high_priority_record?(record)
        return decision(:immediate, "priority_signal")
      end

      if article.summary.blank?
        return decision(:immediate, "missing_summary")
      end

      if article.language.blank?
        return decision(:immediate, "missing_language")
      end

      if claim_summary.blank?
        return decision(:immediate, "missing_claim")
      end

      if claim_summary[:event_family] == "general"
        return decision(:immediate, "general_claim")
      end

      if claim_summary[:confidence].to_f < 0.8
        return decision(:immediate, "low_claim_confidence")
      end

      if article.content_scope == "adjacent"
        return decision(:soon, "adjacent_scope")
      end

      skip("no_trigger")
    end

    private

    def fetch(record, key)
      record[key] || record[key.to_s]
    end

    def rss_article?(article)
      article.metadata.to_h["transport_source"] == "rss"
    end

    def stale_article?(article)
      reference_time = article.published_at || article.fetched_at || article.created_at
      reference_time.present? && reference_time < 24.hours.ago
    end

    def blocked_domain?(domain)
      return false if domain.blank?

      failures = Rails.cache.read(cache_key("domain_failures", domain)) || 0
      cooldown_until = Rails.cache.read(cache_key("domain_cooldown", domain))
      failures >= 3 && cooldown_until.present? && cooldown_until > Time.current
    end

    def high_priority_record?(record)
      return false unless record

      %w[high critical].include?(fetch(record, :threat_level).to_s) ||
        %w[conflict cyber disaster unrest health].include?(fetch(record, :category).to_s)
    end

    def should_attempt_hydration?(article)
      decision = hydrate_decision(article)
      decision[:priority] != :skip
    end

    def mark_queued(article, reason, now)
      return false if %w[queued hydrating hydrated].include?(article.hydration_status)

      article.update_columns(
        hydration_status: "queued",
        hydration_error: reason,
        updated_at: now
      )
    end

    def mark_attempt_started(article)
      article.update_columns(
        hydration_status: "hydrating",
        hydration_attempts: article.hydration_attempts.to_i + 1,
        hydration_last_attempted_at: Time.current,
        updated_at: Time.current
      )
    end

    def mark_failure(article, error_code)
      domain = article.publisher_domain
      increment_domain_failure(domain) if domain.present?

      retryable = article.hydration_attempts.to_i < MAX_ATTEMPTS
      status = retryable ? "queued" : "failed"
      article.update_columns(
        hydration_status: status,
        hydration_error: error_code.to_s.first(255),
        updated_at: Time.current
      )

      if retryable
        RssArticleHydrationJob.set(wait: retry_delay_for(article.hydration_attempts.to_i)).perform_later(article.id)
      end
    end

    def increment_domain_failure(domain)
      failures = (Rails.cache.read(cache_key("domain_failures", domain)) || 0) + 1
      Rails.cache.write(cache_key("domain_failures", domain), failures, expires_in: 6.hours)
      if failures >= 3
        Rails.cache.write(cache_key("domain_cooldown", domain), 30.minutes.from_now, expires_in: 30.minutes)
      end
    end

    def clear_domain_failure(domain)
      Rails.cache.delete(cache_key("domain_failures", domain))
      Rails.cache.delete(cache_key("domain_cooldown", domain))
    end

    def cache_key(prefix, value)
      "rss_hydration:#{prefix}:#{value}"
    end

    def fetch_and_extract(url, limit: 3)
      current_url = url
      redirects = 0

      while current_url.present? && redirects <= limit
        uri = URI(current_url)
        response = perform_request(uri)

        case response
        when Net::HTTPSuccess
          return extract_from_html(response.body, uri)
        when Net::HTTPRedirection
          location = response["location"]
          break if location.blank?

          current_url = URI.join(current_url, location).to_s
          redirects += 1
        else
          return nil
        end
      end

      nil
    end

    def perform_request(uri)
      Net::HTTP.start(uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: FETCH_TIMEOUT,
        read_timeout: FETCH_TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "GlobeTracker/1.0 (rss hydration)"
        request["Accept-Language"] = "en;q=0.7,*;q=0.3"
        http.request(request)
      end
    end

    def extract_from_html(html, uri)
      document = Nokogiri::HTML(html)

      canonical_url = absolute_url(
        first_content(document,
          "link[rel='canonical']@href",
          "meta[property='og:url']@content",
          "meta[name='twitter:url']@content"
        ),
        uri
      )
      title = first_content(document, "meta[property='og:title']@content", "title")
      summary = first_content(
        document,
        "meta[property='og:description']@content",
        "meta[name='description']@content",
        "meta[name='twitter:description']@content"
      )
      summary ||= paragraph_excerpt(document)
      language = first_content(document, "html@lang", "meta[property='og:locale']@content")
      published_at = first_content(
        document,
        "meta[property='article:published_time']@content",
        "meta[name='article:published_time']@content",
        "time[datetime]@datetime"
      )

      {
        canonical_url: canonical_url,
        title: normalize_text(title, 500),
        summary: normalize_text(summary, MAX_BODY_CHARS),
        language: normalize_language(language),
        published_at: parse_time(published_at),
      }.compact
    end

    def apply_hydration(article, extracted)
      now = Time.current
      previous_summary = article.summary

      updates = {
        title: preferred_text(article.title, extracted[:title]),
        summary: better_summary(article.summary, extracted[:summary]),
        language: preferred_text(article.language, extracted[:language]),
        published_at: article.published_at || extracted[:published_at],
        hydration_status: "hydrated",
        hydrated_at: now,
        hydration_error: nil,
        updated_at: now,
      }

      hydrated_canonical_url = extracted[:canonical_url]
      if hydrated_canonical_url.present? && can_replace_canonical_url?(article, hydrated_canonical_url)
        updates[:canonical_url] = hydrated_canonical_url
      end

      article.update_columns(
        **updates,
        metadata: article.metadata.to_h.merge(
          "hydrated_summary_present" => updates[:summary].present?,
          "hydrated_language" => updates[:language],
          "hydrated_canonical_url" => hydrated_canonical_url,
          "hydration_source" => "article_page"
        )
      )

      clear_domain_failure(article.publisher_domain) if article.publisher_domain.present?

      rerun_claims(article) if should_rerun_claims?(article, previous_summary)
    end

    def should_rerun_claims?(article, previous_summary)
      return true if previous_summary.blank? && article.summary.present?
      return true if article.language.present?

      claim = article.news_claims.find_by(primary: true)
      claim.blank? || claim.event_family == "general"
    end

    def rerun_claims(article)
      NewsClaimRecorder.record_all([
        {
          news_article_id: article.id,
          title: article.title,
          summary: article.summary,
          published_at: article.published_at,
          content_scope: article.content_scope,
        },
      ])
      NewsStoryClusterer.recluster_article(article)
    end

    def can_replace_canonical_url?(article, canonical_url)
      return false if canonical_url.blank? || canonical_url == article.canonical_url

      !NewsArticle.where(canonical_url: canonical_url).where.not(id: article.id).exists?
    end

    def better_summary(current_summary, new_summary)
      return current_summary if new_summary.blank?
      return new_summary if current_summary.blank?

      new_summary.length > current_summary.length ? new_summary : current_summary
    end

    def preferred_text(current_value, new_value)
      current_value.present? ? current_value : new_value
    end

    def first_content(document, *selectors)
      selectors.each do |selector|
        attr_match = selector.match(/\A(.+)@([a-zA-Z:_-]+)\z/)
        if attr_match
          node = document.at_css(attr_match[1])
          value = node&.attr(attr_match[2])
        else
          value = document.at_css(selector)&.text
        end
        normalized = normalize_text(value, MAX_BODY_CHARS)
        return normalized if normalized.present?
      end

      nil
    end

    def paragraph_excerpt(document)
      article_text = document.css("article p").map(&:text).join(" ").presence ||
        document.css("main p").map(&:text).join(" ").presence ||
        document.css("p").map(&:text).join(" ")

      normalize_text(article_text, MAX_BODY_CHARS)
    end

    def normalize_text(value, max_length)
      return nil if value.blank?

      text = value.to_s.scrub("").gsub(/\s+/, " ").strip
      return nil if text.blank?

      text.first(max_length)
    end

    def normalize_language(value)
      return nil if value.blank?

      normalized = value.to_s.downcase.tr("_", "-")
      normalized = normalized.split("-").first if normalized.include?("-")
      normalized.first(20).presence
    end

    def parse_time(value)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def absolute_url(value, base_uri)
      return nil if value.blank?

      URI.join(base_uri.to_s, value.to_s).to_s
    rescue URI::InvalidURIError
      nil
    end

    def hydration_delay_for(priority)
      case priority
      when :immediate
        15.seconds
      when :soon
        2.minutes
      else
        0.seconds
      end
    end

    def retry_delay_for(attempts)
      case attempts
      when 0..1
        5.minutes
      when 2
        20.minutes
      else
        0.seconds
      end
    end

    def decision(priority, reason)
      { priority: priority, reason: reason }
    end

    def skip(reason)
      decision(:skip, reason)
    end
  end
end
