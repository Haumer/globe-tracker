module Api
  class SubmarineCablesController < ApplicationController
    skip_before_action :authenticate_user!

    CABLE_GEO_URL = "https://www.submarinecablemap.com/api/v3/cable/cable-geo.json"
    LANDING_GEO_URL = "https://www.submarinecablemap.com/api/v3/landing-point/landing-point-geo.json"

    def index
      # Refresh cable data if stale (older than 7 days) or empty
      if SubmarineCable.count == 0 || SubmarineCable.maximum(:fetched_at)&.before?(7.days.ago)
        refresh_cables
      end

      cables = SubmarineCable.all
      render json: {
        cables: cables.map { |c|
          {
            id: c.cable_id,
            name: c.name,
            color: c.color,
            coordinates: c.coordinates,
          }
        },
        landingPoints: landing_points_cached,
      }
    end

    private

    def refresh_cables
      require "net/http"
      require "json"

      # Fetch cable routes
      uri = URI(CABLE_GEO_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 60
      response = http.request(Net::HTTP::Get.new(uri))

      return unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      features = data["features"] || []
      now = Time.current

      # Group segments by cable_id (some cables have multiple segments)
      cables_by_id = {}
      features.each do |f|
        props = f["properties"] || {}
        cid = props["id"]
        next if cid.blank?

        cables_by_id[cid] ||= {
          cable_id: cid,
          name: props["name"],
          color: props["color"] || "#939597",
          coordinates: [],
          fetched_at: now,
          created_at: now,
          updated_at: now,
        }
        # MultiLineString coordinates — append all segments
        coords = f.dig("geometry", "coordinates")
        cables_by_id[cid][:coordinates].concat(coords) if coords.is_a?(Array)
      end

      records = cables_by_id.values

      SubmarineCable.upsert_all(records, unique_by: :cable_id) if records.any?
    rescue StandardError => e
      Rails.logger.error("SubmarineCables refresh error: #{e.message}")
    end

    def landing_points_cached
      Rails.cache.fetch("submarine_landing_points", expires_in: 7.days) do
        require "net/http"
        require "json"

        uri = URI(LANDING_GEO_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = 60
        response = http.request(Net::HTTP::Get.new(uri))

        return [] unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        (data["features"] || []).filter_map do |f|
          coords = f.dig("geometry", "coordinates")
          props = f["properties"] || {}
          next if coords.nil? || coords.length < 2

          {
            id: props["id"],
            name: props["name"],
            lng: coords[0].to_f,
            lat: coords[1].to_f,
          }
        end
      end
    end
  end
end
