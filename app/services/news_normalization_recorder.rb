require "addressable/uri"
require "public_suffix"
require "set"

class NewsNormalizationRecorder
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
      publisher_domain = publisher_domain_for(record_url, ingest)
      publisher_name = publisher_name_for(record, ingest, publisher_domain)
      source_kind = source_kind_for(record, ingest, publisher_name, publisher_domain)
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

    def source_kind_for(record, ingest, publisher_name, publisher_domain)
      transport_source = fetch(record, :source).to_s
      return "wire" if wire_source?(publisher_name, publisher_domain)
      return "aggregator" if transport_source == "gdelt" && publisher_domain.blank?
      return "platform" if ingest&.source_feed.to_s == "hackernews"

      "publisher"
    end

    def wire_source?(publisher_name, publisher_domain)
      normalized_name = publisher_name.to_s.downcase
      normalized_domain = publisher_domain.to_s.downcase

      normalized_name.include?("reuters") ||
        normalized_name == "ap" ||
        normalized_name.include?("associated press") ||
        normalized_name == "afp" ||
        normalized_name.include?("agence france-presse") ||
        normalized_domain.include?("reuters.com") ||
        normalized_domain.include?("apnews.com") ||
        normalized_domain.include?("afp.com")
    end

    def publisher_name_for(record, ingest, publisher_domain)
      raw_payload = ingest&.raw_payload || {}

      candidates = [
        raw_payload.dig("source", "name"),
        raw_payload["source_name"],
        raw_payload["source"],
        fetch(record, :name),
        scrub_string(ingest&.source_feed, 255),
        humanized_domain_name(publisher_domain),
      ]

      candidates.each do |candidate|
        name = normalize_source_name(candidate)
        return name if name.present?
      end

      nil
    end

    def normalize_source_name(value)
      return nil if value.blank?

      cleaned = value.to_s.scrub("").strip
      return nil if cleaned.blank?

      cleaned = cleaned.sub(/\AGN:\s*/i, "")
      cleaned = cleaned.gsub(/\s+/, " ")
      cleaned[0...200]
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
