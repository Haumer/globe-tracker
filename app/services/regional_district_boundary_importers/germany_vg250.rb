require "json"
require "net/http"
require "time"
require "uri"

require_relative "support"

module RegionalDistrictBoundaryImporters
  class GermanyVg250
    include Support

    DATASET_URL = "https://sgx.geodatenzentrum.de/wfs_vg250?service=WFS&version=2.0.0&request=GetFeature&typeNames=vg250:vg250_krs&outputFormat=application/json&srsName=EPSG:4326".freeze
    SOURCE_PAGE_URL = "https://gdz.bkg.bund.de/index.php/default/open-data/wfs-verwaltungsgebiete-1-250-000-stand-01-01-wfs-vg250.html".freeze
    OUTPUT_PATH = Support::ROOT.join("db", "data", "regional_district_boundary_sources", "germany_vg250_districts.geojson").freeze

    STATE_NAMES = {
      "BW" => "Baden-Wuerttemberg",
      "BY" => "Bavaria",
      "BE" => "Berlin",
      "BB" => "Brandenburg",
      "HB" => "Bremen",
      "HH" => "Hamburg",
      "HE" => "Hesse",
      "MV" => "Mecklenburg-Vorpommern",
      "NI" => "Lower Saxony",
      "NW" => "North Rhine-Westphalia",
      "RP" => "Rhineland-Palatinate",
      "SL" => "Saarland",
      "SN" => "Saxony",
      "ST" => "Saxony-Anhalt",
      "SH" => "Schleswig-Holstein",
      "TH" => "Thuringia"
    }.freeze

    class << self
      def call
        payload = Support.fetch_json(DATASET_URL)
        features = Array(payload["features"]).filter_map { |feature| build_feature(feature) }

        {
          "type" => "FeatureCollection",
          "metadata" => {
            "source_key" => "de_vg250_districts",
            "source_name" => "BKG VG250 Kreise",
            "source_url" => DATASET_URL,
            "source_page_url" => SOURCE_PAGE_URL,
            "country_codes" => ["DE", "DEU"],
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
        district_code = properties["ags"].to_s.strip
        name = properties["gen"].to_s.strip
        return nil if district_code.empty? || name.empty?

        geometry = Support.compact_geometry(feature["geometry"])
        centroid = Support.geometry_centroid(geometry) || {}
        state_code = properties["lkz"].to_s.strip
        state_name = STATE_NAMES[state_code] || state_code
        boundary_names = [name, "#{properties['bez']} #{name}".strip].uniq

        {
          "type" => "Feature",
          "id" => "district-deu-#{district_code}",
          "geometry" => geometry,
          "properties" => {
            "id" => "district-deu-#{district_code}",
            "geography_key" => "district:deu:#{district_code}",
            "source_geo" => district_code,
            "native_level" => "kreis",
            "name" => name,
            "boundary_names" => boundary_names,
            "region_name" => state_name,
            "country_code" => "DE",
            "country_code_alpha3" => "DEU",
            "country_name" => "Germany",
            "state_code" => state_code,
            "state_iso" => "DE-#{state_code}",
            "official_type" => properties["bez"],
            "source_key" => "de_vg250_districts",
            "source_name" => "BKG VG250 Kreise",
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
