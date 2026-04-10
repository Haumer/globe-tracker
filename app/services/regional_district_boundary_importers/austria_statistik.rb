require "json"
require "time"

require_relative "support"

module RegionalDistrictBoundaryImporters
  class AustriaStatistik
    include Support

    DATASET_URL = "https://www.statistik.at/gs-open/GEODATA/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=GEODATA:STATISTIK_AUSTRIA_POLBEZ_20250101&outputFormat=application/json&srsName=EPSG:4326".freeze
    SOURCE_PAGE_URL = "https://data.statistik.gv.at/web/meta.jsp?dataset=OGDEXT_POLBEZ_1".freeze
    OUTPUT_PATH = Support::ROOT.join("db", "data", "regional_district_boundary_sources", "austria_statistik_districts.geojson").freeze

    STATE_NAMES = {
      "1" => "Burgenland",
      "2" => "Carinthia",
      "3" => "Lower Austria",
      "4" => "Upper Austria",
      "5" => "Salzburg",
      "6" => "Styria",
      "7" => "Tyrol",
      "8" => "Vorarlberg",
      "9" => "Vienna"
    }.freeze

    class << self
      def call
        payload = Support.fetch_json(DATASET_URL)
        features = Array(payload["features"]).filter_map { |feature| build_feature(feature) }

        {
          "type" => "FeatureCollection",
          "metadata" => {
            "source_key" => "at_statistik_districts",
            "source_name" => "Statistik Austria Political Districts",
            "source_url" => DATASET_URL,
            "source_page_url" => SOURCE_PAGE_URL,
            "country_codes" => ["AT", "AUT"],
            "generated_at" => Time.now.utc.iso8601,
            "feature_count" => features.length
          },
          "features" => features
        }
      end

      def write!
        payload = call
        FileUtils.mkdir_p(OUTPUT_PATH.dirname)
        File.write(OUTPUT_PATH, JSON.generate(payload))
        payload
      end

      private

      def build_feature(feature)
        properties = feature["properties"] || {}
        district_code = properties["g_id"].to_s.strip
        name = properties["g_name"].to_s.strip
        return nil if district_code.empty? || name.empty?

        geometry = Support.compact_geometry(feature["geometry"])
        centroid = Support.geometry_centroid(geometry) || {}
        state_name = STATE_NAMES[district_code[0]]

        {
          "type" => "Feature",
          "id" => "district-aut-#{district_code}",
          "geometry" => geometry,
          "properties" => {
            "id" => "district-aut-#{district_code}",
            "geography_key" => "district:aut:#{district_code}",
            "source_geo" => district_code,
            "native_level" => "bezirk",
            "name" => name,
            "boundary_names" => [name],
            "region_name" => state_name,
            "country_code" => "AT",
            "country_code_alpha3" => "AUT",
            "country_name" => "Austria",
            "source_key" => "at_statistik_districts",
            "source_name" => "Statistik Austria Political Districts",
            "source_url" => DATASET_URL,
            "source_page_url" => SOURCE_PAGE_URL,
            "latitude" => centroid["latitude"],
            "longitude" => centroid["longitude"]
          }
        }
      end
    end
  end
end
