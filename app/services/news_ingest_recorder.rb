require "digest"

class NewsIngestRecorder
  class << self
    def record_all(items)
      return {} if items.blank?

      now = Time.current
      rows_by_hash = {}
      key_by_hash = Hash.new { |h, k| h[k] = [] }

      items.each do |item|
        row = build_row(item, now)
        next unless row

        rows_by_hash[row[:content_hash]] = merge_rows(rows_by_hash[row[:content_hash]], row)
        key = item[:item_key].presence
        key_by_hash[row[:content_hash]] << key if key
      end

      rows = rows_by_hash.values
      return {} if rows.empty?

      NewsIngest.upsert_all(rows, unique_by: :content_hash)
      digest_to_id = NewsIngest.where(content_hash: rows.map { |row| row[:content_hash] }.uniq)
        .pluck(:content_hash, :id)
        .to_h

      key_by_hash.each_with_object({}) do |(digest, keys), mapping|
        ingest_id = digest_to_id[digest]
        next unless ingest_id

        keys.each { |key| mapping[key] = ingest_id }
      end
    rescue StandardError => e
      Rails.logger.warn("NewsIngestRecorder: #{e.message}")
      {}
    end

    private

    def merge_rows(existing_row, new_row)
      return new_row unless existing_row

      existing_row.merge(
        external_id: existing_row[:external_id].presence || new_row[:external_id],
        raw_summary: existing_row[:raw_summary].presence || new_row[:raw_summary],
        fetched_at: [ existing_row[:fetched_at], new_row[:fetched_at] ].compact.max,
        http_status: new_row[:http_status] || existing_row[:http_status],
        updated_at: new_row[:updated_at]
      )
    end

    def build_row(item, now)
      source_feed = scrub_string(item[:source_feed], 255)
      source_endpoint_url = scrub_string(item[:source_endpoint_url], 2000)
      raw_url = scrub_string(item[:raw_url], 2000)
      raw_title = scrub_string(item[:raw_title], 10_000)
      raw_summary = scrub_string(item[:raw_summary], 20_000)
      raw_published_at = normalize_time(item[:raw_published_at])
      fetched_at = normalize_time(item[:fetched_at]) || now
      payload_format = scrub_string(item[:payload_format], 50) || "json"
      raw_payload = normalize_payload(item[:raw_payload])
      external_id = scrub_string(item[:external_id], 255)

      return nil if source_feed.blank? || source_endpoint_url.blank?
      return nil if raw_payload.blank? && raw_url.blank? && raw_title.blank?

      {
        source_feed: source_feed,
        source_endpoint_url: source_endpoint_url,
        external_id: external_id,
        raw_url: raw_url,
        raw_title: raw_title,
        raw_summary: raw_summary,
        raw_published_at: raw_published_at,
        fetched_at: fetched_at,
        payload_format: payload_format,
        raw_payload: raw_payload,
        http_status: item[:http_status]&.to_i,
        content_hash: content_hash_for(
          source_feed: source_feed,
          source_endpoint_url: source_endpoint_url,
          raw_url: raw_url,
          raw_title: raw_title,
          raw_published_at: raw_published_at,
          raw_payload: raw_payload
        ),
        created_at: now,
        updated_at: now,
      }
    end

    def content_hash_for(source_feed:, source_endpoint_url:, raw_url:, raw_title:, raw_published_at:, raw_payload:)
      Digest::SHA256.hexdigest([
        source_feed,
        source_endpoint_url,
        raw_url,
        raw_title,
        raw_published_at&.iso8601,
        JSON.generate(raw_payload),
      ].join("\n"))
    end

    def normalize_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def normalize_payload(value)
      case value
      when Hash
        value.deep_stringify_keys
      when Array
        value.map { |entry| normalize_payload(entry) }
      when nil
        {}
      else
        JSON.parse(value.to_json)
      end
    rescue StandardError
      { "value" => value.to_s }
    end

    def scrub_string(value, limit)
      return nil if value.nil?

      value.to_s.scrub("")[0...limit]
    end
  end
end
