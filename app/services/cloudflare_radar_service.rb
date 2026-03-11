require "net/http"
require "json"

class CloudflareRadarService
  BASE = "https://api.cloudflare.com/client/v4/radar".freeze
  CACHE_TTL = 3600 # 1 hour

  class << self
    def fetch_snapshot
      token = api_token
      unless token
        Rails.logger.warn("CloudflareRadarService: no CLOUDFLARE_RADAR_TOKEN configured")
        return nil
      end

      # Use DB timestamp as cache check (survives class reloading in dev)
      last = InternetTrafficSnapshot.maximum(:recorded_at)
      return nil if last && (Time.current - last) < CACHE_TTL

      traffic = fetch_top_traffic(token)
      attack_origins = fetch_attack_origins(token)
      attack_targets = fetch_attack_targets(token)
      attack_pairs = fetch_attack_pairs(token)

      now = Time.current
      records = merge_data(traffic, attack_origins, attack_targets, now)

      InternetTrafficSnapshot.insert_all(records) if records.any?

      # Persist attack pairs as JSON in a single-row snapshot attribute
      if attack_pairs.any?
        File.write(attack_pairs_cache_path, attack_pairs.to_json)
      end

      { traffic: traffic, attack_origins: attack_origins, attack_targets: attack_targets, attack_pairs: attack_pairs }
    rescue => e
      Rails.logger.error("CloudflareRadarService: #{e.message}")
      nil
    end

    def cached_attack_pairs
      return [] unless File.exist?(attack_pairs_cache_path)
      JSON.parse(File.read(attack_pairs_cache_path), symbolize_names: true)
    rescue
      []
    end

    def attack_pairs_cache_path
      Rails.root.join("tmp", "cloudflare_attack_pairs.json")
    end

    def api_token
      ENV["CLOUDFLARE_RADAR_TOKEN"].presence ||
        (Rails.application.credentials.dig(:cloudflare, :radar_token) rescue nil)
    end

    private

    def get_json(path, token)
      uri = URI("#{BASE}#{path}")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"

      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        http.request(req)
      end

      return nil unless resp.is_a?(Net::HTTPSuccess)
      JSON.parse(resp.body)
    end

    def fetch_top_traffic(token)
      data = get_json("/http/top/locations/ip_version/IPv4?dateRange=1d&limit=200&format=json", token)
      return [] unless data&.dig("success")

      # Result key is dynamic (first key under result that isn't "meta")
      result_key = data["result"]&.keys&.find { |k| k != "meta" }
      entries = data.dig("result", result_key) || []

      entries.map do |e|
        { code: e["clientCountryAlpha2"], name: e["clientCountryName"], pct: e["value"]&.to_f }
      end
    end

    def fetch_attack_origins(token)
      data = get_json("/attacks/layer3/top/locations?dateRange=1d&limit=100&format=json", token)
      return [] unless data&.dig("success")

      result_key = data["result"]&.keys&.find { |k| k != "meta" }
      entries = data.dig("result", result_key) || []

      entries.map do |e|
        { code: e["clientCountryAlpha2"] || e["originCountryAlpha2"], name: e["clientCountryName"] || e["originCountryName"], pct: e["value"]&.to_f }
      end
    end

    def fetch_attack_targets(token)
      data = get_json("/attacks/layer7/top/locations/target?dateRange=1d&limit=100&format=json", token)
      return [] unless data&.dig("success")

      result_key = data["result"]&.keys&.find { |k| k != "meta" }
      entries = data.dig("result", result_key) || []

      entries.map do |e|
        { code: e["targetCountryAlpha2"], name: e["targetCountryName"], pct: e["value"]&.to_f }
      end
    end

    def fetch_attack_pairs(token)
      data = get_json("/attacks/layer7/top/attacks?dateRange=1d&limit=20&format=json", token)
      return [] unless data&.dig("success")

      result_key = data["result"]&.keys&.find { |k| k != "meta" }
      entries = data.dig("result", result_key) || []

      entries.filter_map do |e|
        origin = e["originCountryAlpha2"]
        target = e["targetCountryAlpha2"]
        next unless origin && target
        { origin: origin, target: target, origin_name: e["originCountryName"], target_name: e["targetCountryName"], pct: e["value"]&.to_f }
      end
    end

    def merge_data(traffic, attack_origins, attack_targets, now)
      countries = {}

      traffic.each do |t|
        countries[t[:code]] ||= { country_code: t[:code], country_name: t[:name], traffic_pct: 0, attack_origin_pct: 0, attack_target_pct: 0, recorded_at: now, created_at: now, updated_at: now }
        countries[t[:code]][:traffic_pct] = t[:pct]
      end

      attack_origins.each do |a|
        countries[a[:code]] ||= { country_code: a[:code], country_name: a[:name], traffic_pct: 0, attack_origin_pct: 0, attack_target_pct: 0, recorded_at: now, created_at: now, updated_at: now }
        countries[a[:code]][:attack_origin_pct] = a[:pct]
      end

      attack_targets.each do |a|
        countries[a[:code]] ||= { country_code: a[:code], country_name: a[:name], traffic_pct: 0, attack_origin_pct: 0, attack_target_pct: 0, recorded_at: now, created_at: now, updated_at: now }
        countries[a[:code]][:attack_target_pct] = a[:pct]
      end

      countries.values
    end
  end
end
