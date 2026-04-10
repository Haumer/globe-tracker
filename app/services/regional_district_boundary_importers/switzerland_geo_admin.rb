require "json"
require "time"
require "uri"

require_relative "support"

module RegionalDistrictBoundaryImporters
  class SwitzerlandGeoAdmin
    include Support

    IDENTIFY_URL = "https://api3.geo.admin.ch/rest/services/ech/MapServer/identify".freeze
    LAYER_ID = "ch.swisstopo.swissboundaries3d-bezirk-flaeche.fill".freeze
    CANTON_LAYER_ID = "ch.swisstopo.swissboundaries3d-kanton-flaeche.fill".freeze
    SOURCE_PAGE_URL = "https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d".freeze
    SOURCE_STAC_URL = "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d".freeze
    OUTPUT_PATH = Support::ROOT.join("db", "data", "regional_district_boundary_sources", "switzerland_geo_admin_districts.geojson").freeze
    SINGLE_DISTRICT_CANTON_CODES = {
      "Appenzell Innerrhoden" => "001600",
      "Basel-Stadt" => "001200",
      "Geneve" => "002500",
      "Genf" => "002500",
      "Genève" => "002500",
      "Glarus" => "000800",
      "Neuchatel" => "002400",
      "Neuchâtel" => "002400",
      "Nidwalden" => "000700",
      "Obwalden" => "000600",
      "Uri" => "000400",
      "Zug" => "000900"
    }.freeze

    class << self
      def call
        district_payload = Support.fetch_json(full_identify_url(
          geometry: "5.22,45.32,11.26,48.25",
          map_extent: "5.22,45.32,11.26,48.25",
          layer_id: LAYER_ID,
          limit: 200
        ))
        canton_payload = Support.fetch_json(full_identify_url(
          geometry: "5.22,45.32,11.26,48.25",
          map_extent: "5.22,45.32,11.26,48.25",
          layer_id: CANTON_LAYER_ID,
          limit: 50
        ))

        features = [
          *Array(district_payload["results"]).filter_map { |feature| build_district_feature(feature) },
          *Array(canton_payload["results"]).filter_map { |feature| build_canton_equivalent_feature(feature) }
        ]

        {
          "type" => "FeatureCollection",
          "metadata" => {
            "source_key" => "ch_geo_admin_districts",
            "source_name" => "swissBOUNDARIES3D District Boundaries",
            "source_url" => IDENTIFY_URL,
            "source_page_url" => SOURCE_PAGE_URL,
            "source_catalog_url" => SOURCE_STAC_URL,
            "country_codes" => ["CH", "CHE"],
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

      def build_district_feature(feature)
        properties = feature["properties"] || {}
        name = properties["name"].to_s.strip
        geometry = Support.compact_geometry(feature["geometry"])
        return nil if name.empty? || geometry.nil?

        centroid = Support.geometry_centroid(geometry) || {}
        source_geo = swiss_source_geo(feature["id"])

        {
          "type" => "Feature",
          "id" => "district-che-#{source_geo}",
          "geometry" => geometry,
          "properties" => {
            "id" => "district-che-#{source_geo}",
            "geography_key" => "district:che:#{source_geo}",
            "source_geo" => source_geo,
            "feature_id" => feature["id"],
            "native_level" => "district",
            "name" => name,
            "boundary_names" => [name, properties["label"]].compact.uniq,
            "region_name" => nil,
            "country_code" => "CH",
            "country_code_alpha3" => "CHE",
            "country_name" => "Switzerland",
            "source_key" => "ch_geo_admin_districts",
            "source_name" => "swissBOUNDARIES3D District Boundaries",
            "source_url" => IDENTIFY_URL,
            "source_page_url" => SOURCE_PAGE_URL,
            "source_catalog_url" => SOURCE_STAC_URL,
            "latitude" => centroid["latitude"],
            "longitude" => centroid["longitude"]
          }
        }
      end

      def build_canton_equivalent_feature(feature)
        properties = feature["properties"] || {}
        name = properties["name"].to_s.strip
        source_geo = SINGLE_DISTRICT_CANTON_CODES[normalize_canton_name(name)]
        return nil if name.empty? || source_geo.nil?

        geometry = Support.compact_geometry(feature["geometry"])
        return nil if geometry.nil?

        centroid = Support.geometry_centroid(geometry) || {}

        {
          "type" => "Feature",
          "id" => "district-che-#{source_geo}",
          "geometry" => geometry,
          "properties" => {
            "id" => "district-che-#{source_geo}",
            "geography_key" => "district:che:#{source_geo}",
            "source_geo" => source_geo,
            "feature_id" => feature["id"],
            "native_level" => "district",
            "name" => name,
            "boundary_names" => [
              name,
              properties["label"],
              "Kanton #{name}",
              "Canton de #{name}"
            ].compact.uniq,
            "region_name" => name,
            "country_code" => "CH",
            "country_code_alpha3" => "CHE",
            "country_name" => "Switzerland",
            "source_key" => "ch_geo_admin_districts",
            "source_name" => "swissBOUNDARIES3D District Boundaries",
            "source_url" => IDENTIFY_URL,
            "source_page_url" => SOURCE_PAGE_URL,
            "source_catalog_url" => SOURCE_STAC_URL,
            "latitude" => centroid["latitude"],
            "longitude" => centroid["longitude"],
            "district_equivalent" => true
          }
        }
      end

      def full_identify_url(geometry:, map_extent:, layer_id:, geometry_type: "esriGeometryEnvelope", limit: 50)
        uri = URI(IDENTIFY_URL)
        uri.query = URI.encode_www_form(
          geometryType: geometry_type,
          geometry: geometry,
          geometryFormat: "geojson",
          imageDisplay: "0,0,0",
          lang: "en",
          layers: "all:#{layer_id}",
          mapExtent: map_extent,
          returnGeometry: "true",
          sr: "4326",
          tolerance: "0",
          limit: limit.to_s
        )
        uri.to_s
      end

      def normalize_canton_name(name)
        name.to_s
          .unicode_normalize(:nfd)
          .gsub(/\p{Mn}/, "")
          .strip
      end

      def swiss_source_geo(raw_id)
        value = raw_id.to_s.strip
        return nil if value.empty?

        value.rjust(6, "0")
      end
    end
  end
end
