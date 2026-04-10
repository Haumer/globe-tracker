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

    def fetch(dataset)
      config = DATASETS[dataset.to_s]
      raise UnsupportedDatasetError, "Unsupported dataset: #{dataset}" unless config

      config[:urls].each do |url|
        payload = http_get(
          URI(url),
          cache_key: config[:cache_key],
          cache_ttl: config[:cache_ttl],
          open_timeout: 10,
          read_timeout: 45
        )
        return payload if valid_feature_collection?(payload)
      end

      cached = Rails.cache.read(config[:cache_key])
      return cached if valid_feature_collection?(cached)

      nil
    end

    private

    def valid_feature_collection?(payload)
      payload.is_a?(Hash) && payload["type"] == "FeatureCollection" && payload["features"].is_a?(Array)
    end
  end
end
