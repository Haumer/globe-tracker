require "fileutils"
require "json"
require "open3"
require "pathname"
require "time"
require "uri"

module RegionalDistrictBoundaryImporters
  module Support
    module_function

    ROOT = Pathname.new(__dir__).join("../../..").expand_path.freeze

    def fetch_json(url)
      stdout, stderr, status = Open3.capture3("curl", "-sL", url)
      error_text = stderr.to_s.strip
      raise "curl failed for #{url}: #{error_text.empty? ? status.exitstatus : error_text}" unless status.success?

      JSON.parse(stdout)
    end

    def fetch_json_with_body(url, body:, headers: {})
      command = ["curl", "-sL", "-X", "POST"]
      headers.each { |key, value| command.concat(["-H", "#{key}: #{value}"]) }
      command.concat(["--data", body, url])

      stdout, stderr, status = Open3.capture3(*command)
      error_text = stderr.to_s.strip
      raise "curl POST failed for #{url}: #{error_text.empty? ? status.exitstatus : error_text}" unless status.success?

      JSON.parse(stdout)
    end

    def normalize_label(value)
      value.to_s
        .unicode_normalize(:nfkd)
        .encode("ASCII", replace: "")
        .downcase
        .gsub(/[^a-z0-9]+/, "")
    end

    def compact_point(point)
      [point[0].to_f.round(5), point[1].to_f.round(5)]
    end

    def compact_geometry(geometry)
      return nil unless geometry.is_a?(Hash)

      case geometry["type"]
      when "Polygon"
        {
          "type" => "Polygon",
          "coordinates" => Array(geometry["coordinates"]).map { |ring| Array(ring).map { |point| compact_point(point) } }
        }
      when "MultiPolygon"
        {
          "type" => "MultiPolygon",
          "coordinates" => Array(geometry["coordinates"]).map do |polygon|
            Array(polygon).map { |ring| Array(ring).map { |point| compact_point(point) } }
          end
        }
      else
        geometry
      end
    end

    def geometry_centroid(geometry)
      points = geometry_points(geometry)
      return nil if points.empty?

      lngs = points.map { |point| point[0].to_f }
      lats = points.map { |point| point[1].to_f }
      return nil if lngs.empty? || lats.empty?

      {
        "longitude" => (lngs.sum / lngs.length).round(5),
        "latitude" => (lats.sum / lats.length).round(5)
      }
    end

    def geometry_points(geometry)
      case geometry&.fetch("type", nil)
      when "Polygon"
        Array(geometry["coordinates"]).flat_map { |ring| Array(ring) }
      when "MultiPolygon"
        Array(geometry["coordinates"]).flat_map { |polygon| Array(polygon).flat_map { |ring| Array(ring) } }
      else
        []
      end
    end
  end
end
