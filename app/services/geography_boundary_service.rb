class GeographyBoundaryService
  class UnsupportedDatasetError < StandardError; end

  DATASETS = {
    "countries" => {
      cache_key: "geography-boundaries:countries:v1",
      cache_ttl: 12.hours,
      urls: [
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson",
        "https://d2ad6b4ur7yvpq.cloudfront.net/naturalearth-3.3.0/ne_110m_admin_0_countries.geojson",
      ],
    },
    "admin1" => {
      cache_key: "geography-boundaries:admin1:v1",
      cache_ttl: 12.hours,
      urls: [
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson",
        "https://d2ad6b4ur7yvpq.cloudfront.net/naturalearth-3.3.0/ne_10m_admin_1_states_provinces.geojson",
      ],
    },
  }.freeze

  class << self
    include HttpClient

    COMPACT_PROPERTY_KEYS = %w[
      adm0_a3
      iso_a2
      iso_3166_2
      name
      name_en
      name_alt
      woe_name
      gn_name
      latitude
      longitude
    ].freeze

    def fetch(dataset, country_codes: nil)
      config = DATASETS[dataset.to_s]
      raise UnsupportedDatasetError, "Unsupported dataset: #{dataset}" unless config

      normalized_country_codes = normalize_country_codes(country_codes)
      if normalized_country_codes.any?
        cached_filtered = Rails.cache.read(filtered_cache_key(config[:cache_key], normalized_country_codes))
        return cached_filtered if valid_feature_collection?(cached_filtered)
      end

      config[:urls].each do |url|
        payload = http_get(
          URI(url),
          cache_key: config[:cache_key],
          cache_ttl: config[:cache_ttl],
          open_timeout: 10,
          read_timeout: 45
        )
        return filtered_payload(payload, country_codes: normalized_country_codes, cache_key: config[:cache_key], cache_ttl: config[:cache_ttl]) if valid_feature_collection?(payload)
      end

      cached = Rails.cache.read(config[:cache_key])
      return filtered_payload(cached, country_codes: normalized_country_codes, cache_key: config[:cache_key], cache_ttl: config[:cache_ttl]) if valid_feature_collection?(cached)

      nil
    end

    private

    def filtered_payload(payload, country_codes:, cache_key: nil, cache_ttl: nil)
      codes = normalize_country_codes(country_codes)
      return payload if codes.empty?

      return compact_filtered_payload(payload, codes) if cache_key.blank?

      variant_cache_key = filtered_cache_key(cache_key, codes)
      Rails.cache.fetch(variant_cache_key, expires_in: cache_ttl || 12.hours) do
        compact_filtered_payload(payload, codes)
      end
    end

    def compact_filtered_payload(payload, codes)
      features = payload.fetch("features", []).select { |feature| feature_matches_country_codes?(feature, codes) }
      {
        "type" => "FeatureCollection",
        "features" => features.map { |feature| compact_feature(feature) },
      }
    end

    def compact_feature(feature)
      properties = feature.fetch("properties", {})
      {
        "type" => "Feature",
        "geometry" => feature["geometry"],
        "properties" => properties.slice(*COMPACT_PROPERTY_KEYS),
      }
    end

    def feature_matches_country_codes?(feature, codes)
      properties = feature.fetch("properties", {})
      feature_codes = %w[adm0_a3 sov_a3 gu_a3 iso_a2].filter_map { |key| properties[key].presence&.upcase }
      (feature_codes & codes).any?
    end

    def normalize_country_codes(country_codes)
      Array(country_codes)
        .flat_map { |value| value.to_s.split(",") }
        .map { |value| value.strip.upcase }
        .reject(&:blank?)
        .uniq
    end

    def filtered_cache_key(base_cache_key, codes)
      [base_cache_key, "filtered", codes.join(","), "v1"].compact.join(":")
    end

    def valid_feature_collection?(payload)
      payload.is_a?(Hash) && payload["type"] == "FeatureCollection" && payload["features"].is_a?(Array)
    end
  end
end
