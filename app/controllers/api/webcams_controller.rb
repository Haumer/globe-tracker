require "net/http"

module Api
  class WebcamsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      north = params[:north]&.to_f
      south = params[:south]&.to_f
      east  = params[:east]&.to_f
      west  = params[:west]&.to_f
      lat   = params[:lat]&.to_f
      lng   = params[:lng]&.to_f

      has_bbox = params[:north].present? && params[:south].present?
      requested_sources = params[:sources]&.split(",")&.map(&:strip) # nil = all

      threads = []

      # Source 1: Windy webcams
      api_key = ENV["WINDY_API_KEY"]
      if api_key.present? && (requested_sources.nil? || requested_sources.include?("windy"))
        threads << Thread.new { fetch_windy(api_key, has_bbox, north, south, east, west, lat, lng) }
      end

      # Source 2: NYC DOT traffic cameras (always fetch if bbox overlaps NYC area)
      if requested_sources.nil? || requested_sources.include?("nycdot")
        if has_bbox
          if bbox_overlaps_nyc?(north, south, east, west)
            threads << Thread.new { fetch_nyc_dot(north, south, east, west) }
          end
        elsif lat && lng && haversine_approx(lat, lng, 40.7128, -74.006) < 100
          threads << Thread.new { fetch_nyc_dot(lat + 0.5, lat - 0.5, lng + 0.5, lng - 0.5) }
        end
      end

      # Source 3: YouTube Live webcams (location-based search)
      yt_key = ENV["YOUTUBE_API_KEY"]
      Rails.logger.info("YouTube check: key=#{yt_key.present?}, sources=#{requested_sources.inspect}, has_bbox=#{has_bbox}")
      if yt_key.present? && (requested_sources.nil? || requested_sources.include?("youtube"))
        center_lat = has_bbox ? (north + south) / 2.0 : lat
        center_lng = has_bbox ? (east + west) / 2.0 : lng
        if center_lat && center_lng
          # Estimate radius from bbox span (km), cap at 500
          radius_km = has_bbox ? [((north - south) * 111 / 2).round, 500].min : 100
          radius_km = [radius_km, 10].max
          threads << Thread.new { fetch_youtube_live(yt_key, center_lat, center_lng, radius_km) }
        end
      end

      if threads.empty?
        return render(json: { error: "No camera sources available" }, status: :service_unavailable)
      end

      all_webcams = threads.flat_map(&:value)
      # Sort: real-time sources first (youtube, nycdot), then live, then timelapse
      all_webcams.sort_by! do |w|
        case w["source"]
        when "youtube", "nycdot" then 0
        else w["live"] ? 1 : 2
        end
      end
      # Hard cap stays bounded, but clustering lets the client handle more cameras safely.
      max = (params[:limit]&.to_i || 80).clamp(1, 160)
      all_webcams = all_webcams.first(max)
      render json: { webcams: all_webcams }
    end

    private

    def bbox_overlaps_nyc?(north, south, east, west)
      # NYC roughly: 40.4-40.95 lat, -74.3 to -73.7 lng
      north >= 40.4 && south <= 40.95 && east >= -74.3 && west <= -73.7
    end

    def haversine_approx(lat1, lng1, lat2, lng2)
      dlat = (lat2 - lat1).abs * 111
      dlng = (lng2 - lng1).abs * 111 * Math.cos(lat1 * Math::PI / 180)
      Math.sqrt(dlat**2 + dlng**2)
    end

    # ── Windy ──────────────────────────────────────────────────

    def fetch_windy(api_key, has_bbox, north, south, east, west, lat, lng)
      limit = (params[:limit]&.to_i || 50).clamp(1, 100)

      # Prefer radius-based nearby query (capped at 100 km) to avoid overwhelming the globe
      if lat && lng
        radius = params[:radius]&.to_i&.clamp(10, 100) || 100
        query = "nearby=#{lat},#{lng},#{radius}"
      elsif has_bbox
        lat_span = north - south
        lng_span = east - west
        lng_span += 360 if lng_span < 0

        grid_lat = lat_span > 4 ? 3 : (lat_span > 2 ? 2 : 1)
        grid_lng = lng_span > 4 ? 3 : (lng_span > 2 ? 2 : 1)

        if grid_lat * grid_lng > 1
          return fetch_windy_grid(api_key, north, south, east, west, grid_lat, grid_lng, limit)
        end

        query = "bbox=#{north},#{east},#{south},#{west}"
      else
        return []
      end

      raw = windy_request(api_key, query, limit)
      raw.map { |w| normalize_windy(w) }
    end

    def fetch_windy_grid(api_key, north, south, east, west, grid_lat, grid_lng, limit)
      lat_step = (north - south) / grid_lat
      lng_span = east - west
      lng_span += 360 if lng_span < 0
      lng_step = lng_span / grid_lng

      subs = []
      grid_lat.times do |r|
        grid_lng.times do |c|
          subs << Thread.new do
            cn = south + (r + 1) * lat_step
            cs = south + r * lat_step
            cw = west + c * lng_step
            ce = west + (c + 1) * lng_step
            windy_request(api_key, "bbox=#{cn},#{ce},#{cs},#{cw}", limit)
          end
        end
      end

      subs.flat_map(&:value).uniq { |w| w["webcamId"] || w["id"] }.map { |w| normalize_windy(w) }
    end

    def windy_request(api_key, query, limit)
      uri = URI("https://api.windy.com/webcams/api/v3/webcams?#{query}&limit=#{limit}&include=images,player,location")
      req = Net::HTTP::Get.new(uri)
      req["x-windy-api-key"] = api_key
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) { |http| http.request(req) }
      resp.is_a?(Net::HTTPSuccess) ? (JSON.parse(resp.body)["webcams"] || []) : []
    rescue => e
      Rails.logger.warn("Windy fetch error: #{e.message}")
      []
    end

    def normalize_windy(w)
      is_live = w.dig("player", "live").present?
      {
        "webcamId" => w["webcamId"] || w["id"],
        "title" => w["title"],
        "source" => "windy",
        "live" => is_live,
        "location" => w["location"],
        "images" => w["images"],
        "player" => w["player"],
        "lastUpdatedOn" => w["lastUpdatedOn"],
        "viewCount" => w["viewCount"],
      }
    end

    # ── NYC DOT Traffic Cameras ────────────────────────────────

    def fetch_nyc_dot(north, south, east, west)
      uri = URI("https://webcams.nyctmc.org/api/cameras")
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      return [] unless resp.is_a?(Net::HTTPSuccess)

      center_lat = (north + south) / 2.0
      center_lng = (east + west) / 2.0

      cameras = JSON.parse(resp.body)
      results = cameras.filter_map do |cam|
        lat = cam["latitude"]&.to_f
        lng = cam["longitude"]&.to_f
        next unless lat && lng
        next unless lat.between?(south, north) && lng.between?(west, east)
        next if cam["isOnline"].to_s == "false"

        dist = haversine_approx(lat, lng, center_lat, center_lng)
        {
          "webcamId" => "nycdot-#{cam['id']}",
          "title" => cam["name"] || "NYC Traffic Cam",
          "source" => "nycdot",
          "live" => true,
          "location" => {
            "latitude" => lat,
            "longitude" => lng,
            "city" => "New York",
            "region" => cam["area"] || "NYC",
            "country" => "United States",
          },
          "images" => {
            "current" => {
              "preview" => cam["imageUrl"] || "https://webcams.nyctmc.org/api/cameras/#{cam['id']}/image",
              "icon" => cam["imageUrl"] || "https://webcams.nyctmc.org/api/cameras/#{cam['id']}/image",
            },
          },
          "player" => nil,
          "lastUpdatedOn" => Time.current.iso8601,
          "viewCount" => nil,
          "_dist" => dist,
        }
      end
      # Return only the nearest cameras within the caller's requested cap.
      limit = (params[:limit]&.to_i || 20).clamp(1, 60)
      results.sort_by! { |c| c["_dist"] }
      results.first(limit).each { |c| c.delete("_dist") }
    rescue => e
      Rails.logger.warn("NYC DOT fetch error: #{e.message}")
      []
    end

    # ── YouTube Live ─────────────────────────────────────────

    def fetch_youtube_live(api_key, lat, lng, radius_km)
      search = youtube_json(
        "https://www.googleapis.com/youtube/v3/search",
        part: "snippet",
        type: "video",
        eventType: "live",
        location: "#{lat},#{lng}",
        locationRadius: "#{radius_km}km",
        q: "webcam OR camera OR live OR street OR traffic OR weather",
        maxResults: (params[:limit]&.to_i || 20).clamp(1, 25),
        key: api_key,
      )
      items = search["items"] || []
      Rails.logger.info("YouTube Live: got #{items.size} results (totalResults: #{search.dig('pageInfo', 'totalResults')})")

      locations = fetch_youtube_locations(api_key, items)
      Rails.logger.info("YouTube Live: found coordinates for #{locations.size} results")

      items.filter_map do |item|
        video_id = item.dig("id", "videoId")
        location = locations[video_id]
        next unless video_id && location

        snippet = item["snippet"] || {}
        {
          "webcamId" => "yt-#{video_id}",
          "title" => snippet["title"] || "YouTube Live",
          "source" => "youtube",
          "live" => true,
          "location" => {
            "latitude" => location[:latitude],
            "longitude" => location[:longitude],
            "city" => nil,
            "region" => nil,
            "country" => nil,
            "description" => location[:description],
          },
          "images" => {
            "current" => {
              "preview" => snippet.dig("thumbnails", "high", "url") || snippet.dig("thumbnails", "medium", "url") || snippet.dig("thumbnails", "default", "url"),
              "icon" => snippet.dig("thumbnails", "default", "url"),
            },
          },
          "player" => {
            "live" => {
              "available" => true,
              "embed" => "https://www.youtube.com/embed/#{video_id}?autoplay=1",
            },
          },
          "videoId" => video_id,
          "channelTitle" => snippet["channelTitle"],
          "lastUpdatedOn" => snippet["publishedAt"],
          "viewCount" => nil,
        }
      end
    rescue => e
      Rails.logger.warn("YouTube Live fetch error: #{e.message}")
      []
    end

    def fetch_youtube_locations(api_key, items)
      video_ids = items.filter_map { |item| item.dig("id", "videoId") }.uniq
      return {} if video_ids.empty?

      details = youtube_json(
        "https://www.googleapis.com/youtube/v3/videos",
        part: "recordingDetails",
        id: video_ids.join(","),
        key: api_key,
      )

      (details["items"] || []).each_with_object({}) do |item, locations|
        raw = item.dig("recordingDetails", "location")
        next unless raw

        latitude = raw["latitude"]&.to_f
        longitude = raw["longitude"]&.to_f
        next unless latitude&.finite? && longitude&.finite?

        locations[item["id"]] = {
          latitude: latitude,
          longitude: longitude,
          description: item.dig("recordingDetails", "locationDescription"),
        }
      end
    end

    def youtube_json(url, **params)
      uri = URI(url)
      uri.query = URI.encode_www_form(params)
      Rails.logger.info("YouTube Live: fetching #{uri}")

      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("YouTube Live: HTTP #{resp.code} — #{resp.body[0..200]}")
        return {}
      end

      JSON.parse(resp.body)
    end
  end
end
