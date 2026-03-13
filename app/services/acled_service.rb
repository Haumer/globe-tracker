require "net/http"
require "json"

class AcledService
  AUTH_URL = "https://acleddata.com/oauth/token".freeze
  API_URL  = "https://acleddata.com/api/acled/read".freeze
  TOKEN_CACHE_KEY = "acled_access_token".freeze
  PAGE_LIMIT = 5000

  class << self
    def refresh_if_stale
      return 0 unless credentials_configured?
      # Only fetch if we have no recent ACLED data (last 7 days)
      latest = ConflictEvent.where("source_headline LIKE '%ACLED%' OR date_start > ?", 60.days.ago)
                            .order(date_start: :desc).first
      if latest && latest.date_start && latest.date_start > 14.days.ago
        Rails.logger.info("AcledService: data is fresh (latest: #{latest.date_start})")
        return 0
      end
      fetch_recent
    end

    def fetch_recent(days_back: 90)
      token = obtain_token
      return 0 unless token

      from_date = (Date.current - days_back).iso8601
      to_date = Date.current.iso8601

      total = 0
      page = 1

      loop do
        uri = URI(API_URL)
        uri.query = URI.encode_www_form(
          event_date: "#{from_date}|#{to_date}",
          event_date_where: "BETWEEN",
          limit: PAGE_LIMIT,
          page: page,
        )

        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{token}"

        resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
          http.request(req)
        end

        unless resp.is_a?(Net::HTTPSuccess)
          Rails.logger.error("AcledService: HTTP #{resp.code} — #{resp.body[0..300]}")
          break
        end

        body = JSON.parse(resp.body)
        events = body["data"] || body
        events = [events] if events.is_a?(Hash)
        break if !events.is_a?(Array) || events.empty?

        upsert_events(events)
        total += events.size

        Rails.logger.info("AcledService: page #{page}, #{total} events so far")

        break if events.size < PAGE_LIMIT
        page += 1
      end

      Rails.logger.info("AcledService: imported #{total} events")
      total
    rescue => e
      Rails.logger.error("AcledService: #{e.class} — #{e.message}")
      0
    end

    def credentials_configured?
      ENV["ACLED_EMAIL"].present? && ENV["ACLED_PASSWORD"].present?
    end

    private

    def obtain_token
      cached = Rails.cache.read(TOKEN_CACHE_KEY)
      return cached if cached.present?

      email = ENV["ACLED_EMAIL"]
      password = ENV["ACLED_PASSWORD"]
      unless email.present? && password.present?
        Rails.logger.warn("AcledService: ACLED_EMAIL / ACLED_PASSWORD not configured")
        return nil
      end

      uri = URI(AUTH_URL)
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(
        username: email,
        password: password,
        grant_type: "password",
        client_id: "acled",
      )

      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
        http.request(req)
      end

      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.error("AcledService: auth failed HTTP #{resp.code} — #{resp.body[0..300]}")
        return nil
      end

      data = JSON.parse(resp.body)
      token = data["access_token"]
      expires_in = (data["expires_in"] || 86400).to_i

      if token.present?
        # Cache with some buffer before expiry
        Rails.cache.write(TOKEN_CACHE_KEY, token, expires_in: expires_in - 300)
        Rails.logger.info("AcledService: obtained access token (expires in #{expires_in}s)")
      end

      token
    rescue => e
      Rails.logger.error("AcledService: auth error — #{e.message}")
      nil
    end

    def upsert_events(events)
      now = Time.current
      records = events.filter_map do |e|
        lat = e["latitude"]&.to_f
        lng = e["longitude"]&.to_f
        next if lat.nil? || lng.nil? || lat == 0.0 && lng == 0.0

        event_id = e["event_id_cnty"] || e["data_id"]
        next unless event_id

        fatalities = e["fatalities"]&.to_i || 0

        {
          external_id: event_id.to_i.nonzero? || event_id.hash.abs,
          conflict_name: e["disorder_type"].presence || e["event_type"] || "Unknown",
          side_a: e["actor1"],
          side_b: e["actor2"],
          country: e["country"],
          region: e["region"],
          where_description: e["location"],
          latitude: lat,
          longitude: lng,
          date_start: e["event_date"],
          date_end: e["event_date"],
          best_estimate: fatalities,
          deaths_a: 0,
          deaths_b: 0,
          deaths_civilians: e["event_type"]&.include?("against civilians") ? fatalities : 0,
          type_of_violence: acled_violence_type(e["event_type"]),
          source_headline: "#{e["sub_event_type"]} — #{e["notes"]&.truncate(200)} [ACLED]",
          created_at: now,
          updated_at: now,
        }
      end

      ConflictEvent.upsert_all(records, unique_by: :external_id) if records.any?
    end

    def acled_violence_type(event_type)
      case event_type
      when /Battles/, /Explosions/, /Military/i then 1  # state-based
      when /Riots/, /Protests/i then 2                  # non-state
      when /against civilians/i then 3                   # one-sided
      else 2
      end
    end
  end
end
