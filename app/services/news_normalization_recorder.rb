require "addressable/uri"
require "public_suffix"
require "set"

class NewsNormalizationRecorder
  PROXY_DISTRIBUTOR_DOMAINS = %w[
    google.com
  ].freeze

  GENERIC_PROXY_FEED_LABELS = [
    "World",
    "Conflict",
    "Iran Conflict",
    "Gaza Conflict",
    "Yemen Houthis",
    "Ukraine War",
    "Disaster",
  ].freeze

  GENERIC_TITLE_PUBLISHER_LABELS = %w[
    analysis
    audio
    commentary
    live
    opinion
    photo
    photos
    report
    update
    updates
    video
  ].freeze

  CANONICAL_PUBLISHER_DOMAINS = {
    "aljazeera.com" => "Al Jazeera",
    "ansa.it" => "ANSA",
    "apnews.com" => "Associated Press",
    "bbc.com" => "BBC",
    "cbsnews.com" => "CBS News",
    "channelnewsasia.com" => "Channel NewsAsia",
    "dw.com" => "DW",
    "elpais.com" => "El Pais",
    "euronews.com" => "Euronews",
    "folha.uol.com.br" => "Folha",
    "france24.com" => "France 24",
    "jpost.com" => "Jerusalem Post",
    "lemonde.fr" => "Le Monde",
    "nbcnews.com" => "NBC News",
    "news.com.au" => "News.com.au",
    "ndtv.com" => "NDTV",
    "news.google.com" => nil,
    "nytimes.com" => "New York Times",
    "pbs.org" => "PBS",
    "premiumtimesng.com" => "Premium Times",
    "repubblica.it" => "La Repubblica",
    "reuters.com" => "Reuters",
    "scmp.com" => "SCMP",
    "spiegel.de" => "Der Spiegel",
    "theguardian.com" => "The Guardian",
    "thehindu.com" => "The Hindu",
    "timesofisrael.com" => "The Times of Israel",
    "vanguardngr.com" => "Vanguard Nigeria",
    "vnexpress.net" => "VnExpress",
    "washingtonpost.com" => "The Washington Post",
    "whitehouse.gov" => "White House",
    "xinhuanet.com" => "Xinhua",
  }.freeze

  CANONICAL_PUBLISHER_LABELS = {
    "al arabiya" => { name: "Al Arabiya", domain: "alarabiya.net" },
    "al arabiya english" => { name: "Al Arabiya", domain: "alarabiya.net" },
    "al jazeera" => { name: "Al Jazeera", domain: "aljazeera.com" },
    "ap" => { name: "Associated Press", domain: "apnews.com" },
    "apnews" => { name: "Associated Press", domain: "apnews.com", source_kind: "wire" },
    "ap news" => { name: "Associated Press", domain: "apnews.com" },
    "associated press" => { name: "Associated Press", domain: "apnews.com" },
    "bangkok post" => { name: "Bangkok Post", domain: "bangkokpost.com" },
    "bbc" => { name: "BBC", domain: "bbc.com" },
    "cbs news" => { name: "CBS News", domain: "cbsnews.com" },
    "channel newsasia" => { name: "Channel NewsAsia", domain: "channelnewsasia.com" },
    "cnn" => { name: "CNN", domain: "cnn.com" },
    "dw" => { name: "DW", domain: "dw.com" },
    "euronews" => { name: "Euronews", domain: "euronews.com" },
    "google" => nil,
    "haaretz" => { name: "Haaretz", domain: "haaretz.com" },
    "iran intl" => { name: "Iran International", domain: "iranintl.com" },
    "jerusalem post" => { name: "Jerusalem Post", domain: "jpost.com" },
    "kyiv independent" => { name: "The Kyiv Independent", domain: "kyivindependent.com" },
    "new york times" => { name: "New York Times", domain: "nytimes.com" },
    "news.com.au" => { name: "News.com.au", domain: "news.com.au" },
    "politico.eu" => { name: "Politico Europe", domain: "politico.eu" },
    "reuters" => { name: "Reuters", domain: "reuters.com", source_kind: "wire" },
    "scmp" => { name: "SCMP", domain: "scmp.com" },
    "sacramento bee" => { name: "Sacramento Bee", domain: "sacbee.com" },
    "tass" => { name: "TASS", domain: "tass.com" },
    "tass.com" => { name: "TASS", domain: "tass.com" },
    "the guardian" => { name: "The Guardian", domain: "theguardian.com" },
    "the hill" => { name: "The Hill", domain: "thehill.com" },
    "the hindu" => { name: "The Hindu", domain: "thehindu.com" },
    "the kyiv independent" => { name: "The Kyiv Independent", domain: "kyivindependent.com" },
    "the national uae" => { name: "The National UAE", domain: "thenationalnews.com" },
    "the new york times" => { name: "New York Times", domain: "nytimes.com" },
    "the times of israel" => { name: "The Times of Israel", domain: "timesofisrael.com" },
    "the washington post" => { name: "The Washington Post", domain: "washingtonpost.com" },
    "white house" => { name: "White House", domain: "whitehouse.gov" },
    "white house gov" => { name: "White House", domain: "whitehouse.gov" },
    "xinhua" => { name: "Xinhua", domain: "xinhuanet.com" },
    "yahoo" => { name: "Yahoo", domain: "yahoo.com" },
  }.freeze

  KNOWN_ORIGIN_SOURCES = [
    {
      canonical_name: "Reuters",
      canonical_domain: "reuters.com",
      source_kind: "wire",
      patterns: [ /\bby\s+reuters\b/i, /\breuters\b/i ],
      direct_domains: %w[reuters.com]
    },
    {
      canonical_name: "Associated Press",
      canonical_domain: "apnews.com",
      source_kind: "wire",
      patterns: [ /\bassociated press\b/i, /\bap news\b/i, /\bby\s+ap\b/i, /\bthe ap\b/i ],
      direct_domains: %w[apnews.com]
    },
    {
      canonical_name: "AFP",
      canonical_domain: "afp.com",
      source_kind: "wire",
      patterns: [ /\bagence france-presse\b/i, /\bafp\b/i ],
      direct_domains: %w[afp.com]
    },
    {
      canonical_name: "Australian Associated Press",
      canonical_domain: nil,
      source_kind: "wire",
      patterns: [ /\baustralian associated press\b/i, /\baap\b/i ],
      direct_domains: []
    },
  ].freeze

  TRACKING_QUERY_PARAMS = %w[
    utm_source utm_medium utm_campaign utm_term utm_content
    utm_id utm_name gclid fbclid mc_cid mc_eid igshid
    ref ref_src rss r_campaignid ga_source ga_medium
  ].to_set.freeze

  class << self
    def record_all(records)
      return {} if records.blank?

      now = Time.current
      ingests_by_id = load_ingests(records)
      normalized_items = records.filter_map do |record|
        normalize_record(record, ingests_by_id[fetch(record, :news_ingest_id)], now)
      end
      return {} if normalized_items.empty?

      source_rows = build_source_rows(normalized_items)
      NewsSource.upsert_all(source_rows, unique_by: :canonical_key) if source_rows.any?
      source_ids = NewsSource.where(canonical_key: source_rows.map { |row| row[:canonical_key] })
        .pluck(:canonical_key, :id)
        .to_h

      article_rows_by_canonical_url = {}
      source_key_by_canonical_url = {}
      record_urls_by_canonical_url = Hash.new { |h, k| h[k] = [] }

      normalized_items.each do |item|
        source_id = source_ids[item[:source_key]]
        next unless source_id

        row = item[:article_row].merge(news_source_id: source_id)
        canonical_url = row[:canonical_url]
        article_rows_by_canonical_url[canonical_url] = merge_article_rows(article_rows_by_canonical_url[canonical_url], row)
        source_key_by_canonical_url[canonical_url] = item[:source_key]
        record_urls_by_canonical_url[canonical_url] << item[:record_url]
      end

      article_rows = article_rows_by_canonical_url.values
      return {} if article_rows.empty?

      NewsArticle.upsert_all(article_rows, unique_by: :canonical_url)

      articles_by_canonical_url = NewsArticle.where(canonical_url: article_rows_by_canonical_url.keys)
        .pluck(:canonical_url, :id, :news_source_id, :content_scope)
        .each_with_object({}) do |(canonical_url, article_id, source_id, content_scope), mapping|
          mapping[canonical_url] = { news_article_id: article_id, news_source_id: source_id, content_scope: content_scope }
        end

      record_urls_by_canonical_url.each_with_object({}) do |(canonical_url, urls), mapping|
        ids = articles_by_canonical_url[canonical_url]
        next unless ids

        urls.each { |url| mapping[url] = ids.dup }
      end
    rescue StandardError => e
      Rails.logger.warn("NewsNormalizationRecorder: #{e.message}")
      {}
    end

    private

    def load_ingests(records)
      ingest_ids = records.filter_map { |record| fetch(record, :news_ingest_id) }.uniq
      return {} if ingest_ids.empty?

      NewsIngest.where(id: ingest_ids).index_by(&:id)
    end

    def build_source_rows(normalized_items)
      rows_by_key = {}

      normalized_items.each do |item|
        row = item[:source_row]
        rows_by_key[row[:canonical_key]] = merge_source_rows(rows_by_key[row[:canonical_key]], row)
      end

      rows_by_key.values
    end

    def normalize_record(record, ingest, now)
      record_url = scrub_string(fetch(record, :url), 2000)
      return nil if record_url.blank?

      canonical_url = canonicalize_url(record_url)
      title = scrub_string(fetch(record, :title), 500)
      published_at = normalize_time(fetch(record, :published_at)) || ingest&.raw_published_at
      fetched_at = normalize_time(fetch(record, :fetched_at)) || ingest&.fetched_at || now
      distributor_domain = publisher_domain_for(record_url, ingest)
      publisher_identity = publisher_identity_for(
        record,
        ingest,
        publisher_domain: distributor_domain,
        title: title
      )
      publisher_name = publisher_identity[:name]
      publisher_domain = publisher_identity[:domain]
      origin_source = origin_source_for(
        record,
        ingest,
        publisher_domain: publisher_domain,
        publisher_name: publisher_name,
        title: title
      )
      origin_source = nil if publisher_matches_origin?(publisher_name, publisher_domain, origin_source)
      source_kind = publisher_identity[:source_kind] ||
        source_kind_for(record, ingest, publisher_name, publisher_domain, origin_source)
      source_key = source_key_for(source_kind, publisher_name, publisher_domain)

      return nil if source_key.blank? || publisher_name.blank?

      source_country = publisher_country_for(ingest)
      language = language_for(ingest)
      summary = scrub_string(ingest&.raw_summary, 20_000)
      scope = NewsScopeClassifier.classify(
        title: title,
        summary: summary,
        category: fetch(record, :category)
      )

      {
        record_url: record_url,
        source_key: source_key,
        source_row: {
          canonical_key: source_key,
          name: publisher_name,
          source_kind: source_kind,
          publisher_domain: publisher_domain,
          publisher_country: source_country,
          publisher_city: nil,
          metadata: {
            "origin_transport" => scrub_string(fetch(record, :source), 100),
            "feed_name" => ingest&.source_feed,
            "distributor_domain" => proxy_distributor_domain?(distributor_domain) ? distributor_domain : nil,
          }.compact,
          created_at: now,
          updated_at: now,
        },
        article_row: {
          news_ingest_id: ingest&.id,
          url: record_url,
          canonical_url: canonical_url,
          title: title,
          summary: summary,
          publisher_name: publisher_name,
          publisher_domain: publisher_domain,
          origin_source_name: origin_source&.dig(:name),
          origin_source_kind: origin_source&.dig(:source_kind),
          origin_source_domain: origin_source&.dig(:domain),
          language: language,
          content_scope: scope[:content_scope],
          scope_reason: scope[:scope_reason],
          published_at: published_at,
          fetched_at: fetched_at,
          normalization_status: "normalized",
          metadata: {
            "transport_source" => scrub_string(fetch(record, :source), 100),
            "feed_name" => ingest&.source_feed,
            "source_endpoint_url" => ingest&.source_endpoint_url,
            "record_name" => scrub_string(fetch(record, :name), 200),
            "category" => scrub_string(fetch(record, :category), 100),
            "credibility" => scrub_string(fetch(record, :credibility), 100),
            "themes" => normalize_array(fetch(record, :themes)),
            "distributor_domain" => proxy_distributor_domain?(distributor_domain) ? distributor_domain : nil,
          }.compact,
          created_at: now,
          updated_at: now,
        },
      }
    end

    def merge_source_rows(existing_row, new_row)
      return new_row unless existing_row

      existing_row.merge(
        name: preferred_value(existing_row[:name], new_row[:name]),
        source_kind: preferred_value(existing_row[:source_kind], new_row[:source_kind]),
        publisher_domain: preferred_value(existing_row[:publisher_domain], new_row[:publisher_domain]),
        publisher_country: preferred_value(existing_row[:publisher_country], new_row[:publisher_country]),
        publisher_city: preferred_value(existing_row[:publisher_city], new_row[:publisher_city]),
        metadata: merge_metadata(existing_row[:metadata], new_row[:metadata]),
        updated_at: new_row[:updated_at]
      )
    end

    def merge_article_rows(existing_row, new_row)
      return new_row unless existing_row

      existing_row.merge(
        news_ingest_id: preferred_value(new_row[:news_ingest_id], existing_row[:news_ingest_id]),
        url: preferred_value(existing_row[:url], new_row[:url]),
        title: preferred_value(existing_row[:title], new_row[:title]),
        summary: preferred_value(existing_row[:summary], new_row[:summary]),
        publisher_name: preferred_value(existing_row[:publisher_name], new_row[:publisher_name]),
        publisher_domain: preferred_value(existing_row[:publisher_domain], new_row[:publisher_domain]),
        origin_source_name: preferred_value(existing_row[:origin_source_name], new_row[:origin_source_name]),
        origin_source_kind: preferred_value(existing_row[:origin_source_kind], new_row[:origin_source_kind]),
        origin_source_domain: preferred_value(existing_row[:origin_source_domain], new_row[:origin_source_domain]),
        language: preferred_value(existing_row[:language], new_row[:language]),
        content_scope: preferred_value(new_row[:content_scope], existing_row[:content_scope]),
        scope_reason: preferred_value(new_row[:scope_reason], existing_row[:scope_reason]),
        published_at: [ existing_row[:published_at], new_row[:published_at] ].compact.min,
        fetched_at: [ existing_row[:fetched_at], new_row[:fetched_at] ].compact.max,
        normalization_status: preferred_value(existing_row[:normalization_status], new_row[:normalization_status]),
        metadata: merge_metadata(existing_row[:metadata], new_row[:metadata]),
        updated_at: new_row[:updated_at]
      )
    end

    def merge_metadata(existing_metadata, new_metadata)
      (existing_metadata || {}).merge(new_metadata || {}) do |_key, old_value, new_value|
        preferred_value(old_value, new_value)
      end
    end

    def preferred_value(existing_value, new_value)
      return existing_value if present_value?(existing_value)

      new_value
    end

    def present_value?(value)
      value.present? && (!value.respond_to?(:empty?) || !value.empty?)
    end

    def source_key_for(source_kind, publisher_name, publisher_domain)
      token = publisher_domain.presence || publisher_name.to_s.parameterize.presence
      return nil if token.blank?

      "#{source_kind}:#{token}"
    end

    def source_kind_for(record, ingest, publisher_name, publisher_domain, origin_source = nil)
      transport_source = fetch(record, :source).to_s
      return "wire" if direct_wire_source?(publisher_name, publisher_domain)
      return "aggregator" if transport_source == "gdelt" && publisher_domain.blank?
      return "platform" if ingest&.source_feed.to_s == "hackernews"
      return "publisher" if origin_source.present?

      "publisher"
    end

    def direct_wire_source?(publisher_name, publisher_domain)
      match_known_origin_source(
        values: [ publisher_name, publisher_domain ],
        publisher_domain: publisher_domain,
        direct_only: true
      ).present?
    end

    def publisher_identity_for(record, ingest, publisher_domain:, title:)
      proxy_identity = proxy_publisher_identity(record, ingest, publisher_domain, title)
      return proxy_identity if proxy_identity.present?

      publisher_name = publisher_name_for(record, ingest, publisher_domain)
      normalized_domain = normalized_publisher_domain(
        publisher_domain,
        publisher_name: publisher_name
      )

      {
        name: publisher_name,
        domain: normalized_domain,
      }
    end

    def publisher_name_for(record, ingest, publisher_domain)
      raw_payload = ingest&.raw_payload || {}

      candidates = [
        raw_payload.dig("source", "name"),
        raw_payload["source_name"],
        humanized_domain_name(publisher_domain),
        scrub_string(ingest&.source_feed, 255),
        fetch(record, :name),
        raw_payload["source"],
      ]

      candidates.each do |candidate|
        name = canonicalize_publisher_label(candidate, fallback_domain: publisher_domain)&.dig(:name) || normalize_source_name(candidate)
        next if origin_like_source_name?(name, publisher_domain)

        return name if name.present?
      end

      nil
    end

    def proxy_publisher_identity(record, ingest, publisher_domain, title)
      return nil unless proxy_distributor_domain?(publisher_domain)

      label = proxy_feed_label(ingest&.source_feed)
      label ||= proxy_feed_label(fetch(record, :name))
      label = nil if generic_proxy_feed_label?(label)
      label ||= publisher_label_from_title(title)
      return nil if label.blank?

      identity = canonicalize_publisher_label(label)
      return nil unless identity.present?

      {
        name: identity[:name],
        domain: normalized_publisher_domain(identity[:domain], publisher_name: identity[:name]),
        source_kind: identity[:source_kind],
      }
    end

    def proxy_distributor_domain?(publisher_domain)
      publisher_domain.present? && PROXY_DISTRIBUTOR_DOMAINS.include?(publisher_domain.to_s.downcase)
    end

    def proxy_feed_label(feed_name)
      feed_name = normalize_source_name(feed_name)
      return nil if feed_name.blank?

      feed_name.sub(/\AGN:\s*/i, "").strip
    end

    def generic_proxy_feed_label?(label)
      label.present? && GENERIC_PROXY_FEED_LABELS.include?(label)
    end

    def publisher_label_from_title(title)
      return nil if title.blank?

      segments = title.to_s.split(/\s+[–—-]\s+/).map(&:strip).reject(&:blank?)
      return nil if segments.empty?

      segments.reverse_each do |segment|
        candidate = normalize_source_name(segment)
        next if candidate.blank?

        canonical = canonicalize_publisher_label(candidate)
        return canonical[:name] if canonical.present? && plausible_publisher_label?(canonical[:name])

        next unless plausible_publisher_label?(candidate)

        return candidate
      end

      nil
    end

    def plausible_publisher_label?(candidate)
      return false if candidate.blank?
      return false if candidate.length > 80
      return false if generic_proxy_feed_label?(candidate)
      return false if GENERIC_TITLE_PUBLISHER_LABELS.include?(candidate.to_s.downcase)

      candidate.match?(/[A-Za-z]/)
    end

    def normalize_source_name(value)
      return nil if value.blank?

      cleaned = value.to_s.scrub("").strip
      return nil if cleaned.blank?

      cleaned = cleaned.sub(/\AGN:\s*/i, "")
      cleaned = cleaned.sub(/\ABy\s+/i, "")
      cleaned = cleaned.gsub(/\s+/, " ")
      cleaned[0...200]
    end

    def canonicalize_publisher_label(label, fallback_domain: nil)
      cleaned = normalize_source_name(label)
      return nil if cleaned.blank?

      domain = domain_from_label(cleaned) || fallback_domain
      domain = normalized_publisher_domain(domain, publisher_name: cleaned)

      if domain.present? && CANONICAL_PUBLISHER_DOMAINS.key?(domain)
        canonical_name = CANONICAL_PUBLISHER_DOMAINS[domain]
        return nil if canonical_name.blank?

        return {
          name: canonical_name,
          domain: domain,
          source_kind: known_source_kind_for(canonical_name, domain),
        }
      end

      origin_match = match_known_origin_source(
        values: [ cleaned ],
        publisher_domain: domain,
        direct_only: false
      )
      return origin_match if origin_match.present?

      label_key = source_label_key(cleaned)
      alias_match = CANONICAL_PUBLISHER_LABELS[label_key]
      return alias_match&.dup if alias_match

      if domain.present?
        humanized = humanized_domain_name(domain)
        return {
          name: humanized,
          domain: domain,
          source_kind: known_source_kind_for(humanized, domain),
        } if humanized.present?
      end

      {
        name: cleaned,
        domain: domain,
        source_kind: known_source_kind_for(cleaned, domain),
      }
    end

    def source_label_key(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def domain_from_label(value)
      candidate = value.to_s.downcase.strip
      return nil if candidate.blank?
      return nil unless candidate.include?(".")

      domain_from_url("https://#{candidate}")
    end

    def normalized_publisher_domain(domain, publisher_name:)
      normalized_domain = domain.to_s.downcase.presence
      return nil if proxy_distributor_domain?(normalized_domain)

      known_match = match_known_origin_source(
        values: [ publisher_name, normalized_domain ],
        publisher_domain: normalized_domain,
        direct_only: false
      )
      return known_match[:domain] if known_match&.dig(:domain).present?

      normalized_domain
    end

    def publisher_matches_origin?(publisher_name, publisher_domain, origin_source)
      return false if publisher_name.blank? || origin_source.blank?

      publisher_name == origin_source[:name] &&
        publisher_domain.to_s == origin_source[:domain].to_s
    end

    def known_source_kind_for(name, domain)
      return "wire" if match_known_origin_source(
        values: [ name, domain ],
        publisher_domain: domain,
        direct_only: false
      ).present?

      nil
    end

    def origin_source_for(record, ingest, publisher_domain:, publisher_name:, title:)
      direct_match = match_known_origin_source(
        values: [ publisher_name, publisher_domain ],
        publisher_domain: publisher_domain,
        direct_only: true
      )
      return direct_match if direct_match

      raw_payload = ingest&.raw_payload || {}
      values = [
        title,
        ingest&.raw_title,
        ingest&.raw_summary,
        raw_payload.dig("source", "name"),
        raw_payload["source_name"],
        raw_payload["source"],
        raw_payload["author"],
        fetch(record, :name),
      ]

      match_known_origin_source(
        values: values,
        publisher_domain: publisher_domain,
        direct_only: false
      )
    end

    def origin_like_source_name?(name, publisher_domain)
      return false if name.blank?

      match = match_known_origin_source(
        values: [ name ],
        publisher_domain: publisher_domain,
        direct_only: false
      )
      match.present? && match[:domain].present? && match[:domain] != publisher_domain.to_s.downcase
    end

    def match_known_origin_source(values:, publisher_domain:, direct_only:)
      normalized_domain = publisher_domain.to_s.downcase

      KNOWN_ORIGIN_SOURCES.each do |source|
        direct_domain_match = source[:direct_domains].any? { |domain| domain_matches?(normalized_domain, domain) }
        next if direct_only && !direct_domain_match

        values.each do |value|
          normalized_value = normalize_source_name(value)
          next if normalized_value.blank?

          normalized_value_downcase = normalized_value.downcase
          matched = source[:patterns].any? { |pattern| normalized_value.match?(pattern) }
          matched ||= source[:direct_domains].any? { |domain| domain_matches?(normalized_value_downcase, domain) }
          next unless matched

          return {
            name: source[:canonical_name],
            source_kind: source[:source_kind],
            domain: source[:canonical_domain],
          }
        end
      end

      nil
    end

    def domain_matches?(candidate, domain)
      candidate = candidate.to_s.downcase.strip
      domain = domain.to_s.downcase.strip
      return false if candidate.blank? || domain.blank?

      candidate == domain || candidate.end_with?(".#{domain}")
    end

    def publisher_domain_for(record_url, ingest)
      candidates = [
        domain_from_url(record_url),
        domain_from_url(ingest&.raw_url),
        scrub_string(ingest&.raw_payload&.dig("source", "domain"), 255),
        scrub_string(ingest&.raw_payload&.dig("domain"), 255),
      ]

      candidates.find(&:present?)
    end

    def domain_from_url(url)
      return nil if url.blank?

      uri = Addressable::URI.parse(url.to_s)
      host = uri.host.to_s.downcase.sub(/\Awww\./, "")
      return nil if host.blank?

      PublicSuffix.domain(host)
    rescue StandardError
      nil
    end

    def humanized_domain_name(domain)
      return nil if domain.blank?
      return CANONICAL_PUBLISHER_DOMAINS[domain] if CANONICAL_PUBLISHER_DOMAINS.key?(domain)

      parsed = PublicSuffix.parse(domain)
      label = parsed.sld.to_s
      return nil if label.blank?

      label = label.tr("-", " ").tr("_", " ")
      label.split.map { |part| acronym?(part) ? part.upcase : part.capitalize }.join(" ")
    rescue StandardError
      nil
    end

    def acronym?(value)
      value.length <= 4
    end

    def publisher_country_for(ingest)
      raw_payload = ingest&.raw_payload || {}
      value = raw_payload["source_country"] || raw_payload["locale"] || raw_payload["country"] || raw_payload.dig("source", "country")
      value = value.first if value.is_a?(Array)

      scrub_string(value, 100)&.upcase
    end

    def language_for(ingest)
      raw_payload = ingest&.raw_payload || {}
      scrub_string(raw_payload["language"] || raw_payload["lang"], 20)
    end

    def canonicalize_url(url)
      uri = Addressable::URI.parse(url.to_s.strip)
      uri.scheme = uri.scheme.to_s.downcase.presence || "https"
      uri.host = uri.host.to_s.downcase.presence
      uri.fragment = nil

      normalized_query = normalize_query(uri.query)
      uri.query = normalized_query.presence

      normalized = uri.normalize.to_s
      normalized.sub(%r{/\z}, "")
    rescue StandardError
      url.to_s.scrub("")[0...2000]
    end

    def normalize_query(query)
      return nil if query.blank?

      pairs = Addressable::URI.form_unencode(query).reject do |key, _value|
        TRACKING_QUERY_PARAMS.include?(key.to_s.downcase)
      end
      return nil if pairs.empty?

      Addressable::URI.form_encode(pairs.sort_by { |key, value| [ key.to_s, value.to_s ] })
    end

    def normalize_array(value)
      Array(value).filter_map do |entry|
        scrub_string(entry, 100)
      end
    end

    def normalize_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def scrub_string(value, limit)
      return nil if value.nil?

      value.to_s.scrub("")[0...limit]
    end

    def fetch(record, key)
      record[key] || record[key.to_s]
    end
  end
end
