require "net/http"

module Api
  class WeatherAlertsController < ApplicationController
    skip_before_action :authenticate_user!

    # Returns active severe weather alerts with coordinates.
    # Sources: NWS (US), with room to add EUMETNET/GDACS later.
    def index
      alerts = Rails.cache.fetch("weather_alerts", expires_in: 10.minutes) do
        fetch_nws_alerts
      end

      render json: { alerts: alerts, fetched_at: Time.current.iso8601, count: alerts.size }
    end

    private

    def fetch_nws_alerts
      uri = URI("https://api.weather.gov/alerts/active?status=actual&severity=Extreme,Severe,Moderate")
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "GlobeTracker/1.0 (weather-alerts)"
      req["Accept"] = "application/geo+json"

      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        http.request(req)
      end

      return [] unless resp.is_a?(Net::HTTPSuccess)

      data = JSON.parse(resp.body)
      features = data["features"] || []

      features.filter_map do |f|
        props = f["properties"] || {}
        geo = f["geometry"]

        # Extract centroid from geometry (polygon or point)
        lat, lng = extract_centroid(geo)

        # Fallback: try to geocode from areaDesc if no geometry
        if lat.nil? && props["areaDesc"].present?
          lat, lng = approximate_from_area(props["areaDesc"])
        end

        next unless lat && lng

        {
          event: props["event"],
          severity: props["severity"],
          urgency: props["urgency"],
          certainty: props["certainty"],
          headline: props["headline"],
          description: props["description"]&.slice(0, 500),
          areas: props["areaDesc"]&.slice(0, 200),
          onset: props["onset"],
          expires: props["expires"],
          sender: props["senderName"],
          lat: lat.round(4),
          lng: lng.round(4),
        }
      end
    rescue StandardError => e
      Rails.logger.warn("WeatherAlertsController: #{e.message}")
      []
    end

    def extract_centroid(geo)
      return [nil, nil] unless geo

      case geo["type"]
      when "Point"
        coords = geo["coordinates"]
        [coords[1], coords[0]] if coords&.size == 2
      when "Polygon"
        ring = geo["coordinates"]&.first
        return [nil, nil] unless ring&.any?
        avg_lng = ring.sum { |c| c[0] } / ring.size.to_f
        avg_lat = ring.sum { |c| c[1] } / ring.size.to_f
        [avg_lat.round(4), avg_lng.round(4)]
      when "MultiPolygon"
        all_coords = geo["coordinates"]&.flatten(2) || []
        return [nil, nil] if all_coords.empty?
        avg_lng = all_coords.sum { |c| c[0] } / all_coords.size.to_f
        avg_lat = all_coords.sum { |c| c[1] } / all_coords.size.to_f
        [avg_lat.round(4), avg_lng.round(4)]
      else
        [nil, nil]
      end
    end

    # Very rough US state centroid lookup for alerts without geometry
    STATE_CENTROIDS = {
      "AL" => [32.8, -86.8], "AK" => [64.2, -152.5], "AZ" => [34.0, -111.1],
      "AR" => [35.2, -91.8], "CA" => [36.8, -119.4], "CO" => [39.1, -105.4],
      "CT" => [41.6, -72.7], "DE" => [38.9, -75.5], "FL" => [27.7, -81.5],
      "GA" => [32.2, -83.6], "HI" => [19.9, -155.6], "ID" => [44.1, -114.7],
      "IL" => [40.6, -89.4], "IN" => [40.3, -86.1], "IA" => [41.9, -93.1],
      "KS" => [38.5, -98.8], "KY" => [37.8, -84.3], "LA" => [31.2, -92.3],
      "ME" => [45.3, -69.4], "MD" => [39.0, -76.6], "MA" => [42.4, -71.4],
      "MI" => [44.3, -85.6], "MN" => [46.7, -94.7], "MS" => [32.3, -89.4],
      "MO" => [38.6, -92.2], "MT" => [46.8, -110.4], "NE" => [41.1, -99.8],
      "NV" => [38.8, -116.4], "NH" => [43.5, -71.6], "NJ" => [40.1, -74.4],
      "NM" => [34.8, -106.2], "NY" => [43.0, -75.0], "NC" => [35.6, -79.0],
      "ND" => [47.5, -100.5], "OH" => [40.4, -82.9], "OK" => [35.0, -97.1],
      "OR" => [43.8, -120.6], "PA" => [41.2, -77.2], "RI" => [41.6, -71.5],
      "SC" => [33.8, -81.2], "SD" => [43.9, -99.4], "TN" => [35.5, -86.6],
      "TX" => [31.1, -97.6], "UT" => [39.3, -111.1], "VT" => [44.0, -72.7],
      "VA" => [37.8, -78.2], "WA" => [47.4, -120.7], "WV" => [38.6, -80.5],
      "WI" => [43.8, -88.8], "WY" => [43.1, -107.6],
    }.freeze

    def approximate_from_area(area_desc)
      # Try to match 2-letter state code
      STATE_CENTROIDS.each do |code, coords|
        return coords if area_desc.include?(code)
      end
      [nil, nil]
    end
  end
end
