require "net/http"
require "json"

class ConflictEventService
  extend Refreshable

  BASE_URL = "https://ucdpapi.pcr.uu.se/api/gedevents/24.1".freeze
  PAGE_SIZE = 1000
  DAILY_REQUEST_LIMIT = 5000
  RATE_LIMIT_CACHE_KEY = "ucdp_api_requests_today".freeze

  refreshes model: ConflictEvent, interval: 1.day, column: :updated_at

  class << self
    def refresh_if_stale(force: false, year: Date.current.year - 1)
      return 0 if !force && !stale?
      fetch_recent(year: year)
    end

    def fetch_recent(year: Date.current.year - 1)
      token = api_token
      unless token
        Rails.logger.warn("ConflictEventService: no UCDP_API_TOKEN configured — skipping fetch")
        return 0
      end

      if rate_limit_exhausted?
        Rails.logger.warn("ConflictEventService: daily request limit (#{DAILY_REQUEST_LIMIT}) reached — skipping")
        return 0
      end

      total = 0
      page = 1

      loop do
        if rate_limit_exhausted?
          Rails.logger.warn("ConflictEventService: hit daily limit mid-fetch at page #{page}")
          break
        end

        uri = URI("#{BASE_URL}?pagesize=#{PAGE_SIZE}&page=#{page}&StartDate=#{year}-01-01&EndDate=#{year}-12-31")
        req = Net::HTTP::Get.new(uri)
        req["x-ucdp-access-token"] = token

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
          http.request(req)
        end
        increment_request_count!

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.error("ConflictEventService: HTTP #{response.code} — #{response.body[0..200]}")
          break
        end

        data = JSON.parse(response.body)
        results = data["Result"] || []
        break if results.empty?

        upsert_events(results)
        total += results.size

        Rails.logger.info("ConflictEventService: page #{page}, #{total}/#{data['TotalCount']} events (#{requests_today}/#{DAILY_REQUEST_LIMIT} requests today)")

        break if page >= (data["TotalPages"] || 1)
        page += 1
      end

      Rails.logger.info("ConflictEventService: imported #{total} events (#{requests_today}/#{DAILY_REQUEST_LIMIT} requests used today)")
      total
    rescue => e
      Rails.logger.error("ConflictEventService: #{e.message}")
      0
    end

    def requests_today
      Rails.cache.read(RATE_LIMIT_CACHE_KEY).to_i
    end

    def rate_limit_exhausted?
      requests_today >= DAILY_REQUEST_LIMIT
    end

    def api_token
      ENV["UCDP_API_TOKEN"].presence ||
        (Rails.application.credentials.dig(:ucdp, :api_token) rescue nil)
    end

    private

    def increment_request_count!
      count = requests_today + 1
      # Expire at end of day (UTC)
      ttl = Time.current.end_of_day - Time.current
      Rails.cache.write(RATE_LIMIT_CACHE_KEY, count, expires_in: ttl)
    end

    def upsert_events(results)
      now = Time.current
      records = results.filter_map do |r|
        lat = r["latitude"]&.to_f
        lng = r["longitude"]&.to_f
        next if lat.nil? || lng.nil?

        {
          external_id: r["id"],
          conflict_name: r["conflict_name"],
          side_a: r["side_a"],
          side_b: r["side_b"],
          country: r["country"],
          region: r["region"],
          where_description: r["where_description"],
          latitude: lat,
          longitude: lng,
          date_start: r["date_start"],
          date_end: r["date_end"],
          best_estimate: r["best"]&.to_i || 0,
          deaths_a: r["deaths_a"]&.to_i || 0,
          deaths_b: r["deaths_b"]&.to_i || 0,
          deaths_civilians: r["deaths_civilians"]&.to_i || 0,
          type_of_violence: r["type_of_violence"]&.to_i,
          source_headline: r["source_headline"],
          created_at: now,
          updated_at: now,
        }
      end

      ConflictEvent.upsert_all(records, unique_by: :external_id) if records.any?
    end
  end
end
