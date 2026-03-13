require "net/http"

class CameraRefreshService
  extend HttpClient

  # Minimum interval between API fetches for the same geographic cell.
  # Grid cells are 1° × 1° — prevents hammering APIs when multiple users
  # zoom into the same area.
  CELL_TTL = 10.minutes

  def initialize(north:, south:, east:, west:, lat: nil, lng: nil, sources: nil)
    @north   = north
    @south   = south
    @east    = east
    @west    = west
    @lat     = lat || (north + south) / 2.0
    @lng     = lng || (east + west) / 2.0
    @sources = sources # nil = all
  end

  def refresh
    fetched = 0
    threads = []

    if should_fetch?("windy") && ENV["WINDY_API_KEY"].present?
      threads << Thread.new { fetch_windy }
    end

    if should_fetch?("youtube") && ENV["YOUTUBE_API_KEY"].present? && !youtube_quota_exhausted?
      threads << Thread.new { fetch_youtube }
    end

    if should_fetch?("nycdot") && bbox_overlaps_nyc?
      threads << Thread.new { fetch_nyc_dot }
    end

    results = threads.map(&:value).compact.flatten
    fetched = upsert_cameras(results) if results.any?

    mark_cells_fetched
    fetched
  rescue StandardError => e
    Rails.logger.error("CameraRefreshService: #{e.message}")
    0
  end

  private

  def should_fetch?(source)
    @sources.nil? || @sources.include?(source)
  end

  # ── Cell-based dedup ──────────────────────────────────────

  def cell_keys
    lat_min = @south.floor
    lat_max = @north.ceil
    lng_min = @west.floor
    lng_max = @east.ceil
    keys = []
    (lat_min...lat_max).each do |lat|
      (lng_min...lng_max).each do |lng|
        keys << "camera_cell:#{lat},#{lng}"
      end
    end
    keys
  end

  def cells_recently_fetched?
    cell_keys.all? { |k| Rails.cache.read(k).present? }
  end

  def mark_cells_fetched
    cell_keys.each { |k| Rails.cache.write(k, true, expires_in: CELL_TTL) }
  end

  # ── Upsert ────────────────────────────────────────────────

  def upsert_cameras(records)
    now = Time.current
    rows = records.map do |r|
      ttl = Camera::STALE_AFTER[r[:source]] || 30.days
      {
        webcam_id:     r[:webcam_id],
        source:        r[:source],
        title:         r[:title],
        latitude:      r[:latitude],
        longitude:     r[:longitude],
        status:        "active",
        camera_type:   r[:camera_type],
        is_live:       r[:is_live] || false,
        player_url:    r[:player_url],
        image_url:     r[:image_url],
        preview_url:   r[:preview_url],
        city:          r[:city],
        region:        r[:region],
        country:       r[:country],
        video_id:      r[:video_id],
        channel_title: r[:channel_title],
        view_count:    r[:view_count],
        metadata:      r[:metadata] || {},
        last_checked_at: now,
        fetched_at:    now,
        expires_at:    now + ttl,
        created_at:    now,
        updated_at:    now,
      }
    end

    Camera.upsert_all(rows, unique_by: :idx_cameras_dedup, update_only: [
      :title, :latitude, :longitude, :status, :camera_type, :is_live,
      :player_url, :image_url, :preview_url, :city, :region, :country,
      :video_id, :channel_title, :view_count, :metadata,
      :last_checked_at, :fetched_at, :expires_at,
    ])

    rows.size
  end

  # ── Windy ─────────────────────────────────────────────────

  def fetch_windy
    api_key = ENV["WINDY_API_KEY"]
    limit = 50

    # Grid subdivision for large viewports
    lat_span = @north - @south
    lng_span = @east - @west
    lng_span += 360 if lng_span < 0

    grid_lat = lat_span > 4 ? 3 : (lat_span > 2 ? 2 : 1)
    grid_lng = lng_span > 4 ? 3 : (lng_span > 2 ? 2 : 1)

    raw = if grid_lat * grid_lng > 1
      fetch_windy_grid(api_key, grid_lat, grid_lng, limit)
    else
      windy_request(api_key, "bbox=#{@north},#{@east},#{@south},#{@west}", limit)
    end

    raw.map { |w| normalize_windy(w) }
  rescue StandardError => e
    Rails.logger.warn("CameraRefreshService Windy: #{e.message}")
    []
  end

  def fetch_windy_grid(api_key, grid_lat, grid_lng, limit)
    lat_step = (@north - @south) / grid_lat
    lng_span = @east - @west
    lng_span += 360 if lng_span < 0
    lng_step = lng_span / grid_lng

    subs = []
    grid_lat.times do |r|
      grid_lng.times do |c|
        subs << Thread.new do
          cn = @south + (r + 1) * lat_step
          cs = @south + r * lat_step
          cw = @west + c * lng_step
          ce = @west + (c + 1) * lng_step
          windy_request(api_key, "bbox=#{cn},#{ce},#{cs},#{cw}", limit)
        end
      end
    end

    subs.flat_map(&:value).uniq { |w| w["webcamId"] || w["id"] }
  end

  def windy_request(api_key, query, limit)
    uri = URI("https://api.windy.com/webcams/api/v3/webcams?#{query}&limit=#{limit}&include=images,player,location")
    req = Net::HTTP::Get.new(uri)
    req["x-windy-api-key"] = api_key
    resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) { |http| http.request(req) }
    resp.is_a?(Net::HTTPSuccess) ? (JSON.parse(resp.body)["webcams"] || []) : []
  rescue => e
    Rails.logger.warn("CameraRefreshService windy_request: #{e.message}")
    []
  end

  def normalize_windy(w)
    is_live = w.dig("player", "live").present?
    live_url = extract_windy_url(w.dig("player", "live"))
    day_url  = extract_windy_url(w.dig("player", "day"))
    {
      webcam_id:   (w["webcamId"] || w["id"]).to_s,
      source:      "windy",
      title:       w["title"],
      latitude:    w.dig("location", "latitude")&.to_f,
      longitude:   w.dig("location", "longitude")&.to_f,
      camera_type: is_live ? "live" : "timelapse",
      is_live:     is_live,
      player_url:  live_url || day_url,
      image_url:   w.dig("images", "current", "preview") || w.dig("images", "daylight", "preview"),
      preview_url: w.dig("images", "current", "icon") || w.dig("images", "daylight", "icon"),
      city:        w.dig("location", "city"),
      region:      w.dig("location", "region"),
      country:     w.dig("location", "country"),
      view_count:  w["viewCount"],
      metadata:    { lastUpdatedOn: w["lastUpdatedOn"] },
    }
  end

  def extract_windy_url(player_hash)
    return nil unless player_hash.is_a?(Hash)
    player_hash["embed"] || player_hash["available"]&.then { |_| nil }
  end

  # ── YouTube ───────────────────────────────────────────────

  YOUTUBE_QUOTA_COOLDOWN = 1.hour

  def fetch_youtube
    return [] if youtube_quota_exhausted?

    api_key = ENV["YOUTUBE_API_KEY"]
    radius_km = [(((@north - @south) * 111) / 2).round, 500].min
    radius_km = [radius_km, 10].max

    search = youtube_json(
      "https://www.googleapis.com/youtube/v3/search",
      part: "snippet", type: "video", eventType: "live",
      location: "#{@lat},#{@lng}",
      locationRadius: "#{radius_km}km",
      q: "webcam OR camera OR live OR street OR traffic OR weather",
      maxResults: 25,
      key: api_key,
    )

    if search[:quota_exceeded]
      mark_youtube_quota_exhausted!
      return []
    end

    items = search["items"] || []
    return [] if items.empty?

    locations = fetch_youtube_locations(api_key, items)

    items.filter_map do |item|
      video_id = item.dig("id", "videoId")
      loc = locations[video_id]
      next unless video_id && loc

      snippet = item["snippet"] || {}
      {
        webcam_id:     "yt-#{video_id}",
        source:        "youtube",
        title:         snippet["title"] || "YouTube Live",
        latitude:      loc[:latitude],
        longitude:     loc[:longitude],
        camera_type:   "live",
        is_live:       true,
        player_url:    "https://www.youtube.com/embed/#{video_id}?autoplay=1",
        image_url:     snippet.dig("thumbnails", "high", "url") || snippet.dig("thumbnails", "medium", "url"),
        preview_url:   snippet.dig("thumbnails", "default", "url"),
        video_id:      video_id,
        channel_title: snippet["channelTitle"],
        metadata:      { publishedAt: snippet["publishedAt"] },
      }
    end
  rescue StandardError => e
    Rails.logger.warn("CameraRefreshService YouTube: #{e.message}")
    []
  end

  def fetch_youtube_locations(api_key, items)
    video_ids = items.filter_map { |item| item.dig("id", "videoId") }.uniq
    return {} if video_ids.empty?

    details = youtube_json(
      "https://www.googleapis.com/youtube/v3/videos",
      part: "recordingDetails", id: video_ids.join(","), key: api_key,
    )

    (details["items"] || []).each_with_object({}) do |item, locs|
      raw = item.dig("recordingDetails", "location")
      next unless raw
      lat = raw["latitude"]&.to_f
      lng = raw["longitude"]&.to_f
      next unless lat&.finite? && lng&.finite?
      locs[item["id"]] = { latitude: lat, longitude: lng }
    end
  end

  def youtube_json(url, **params)
    uri = URI(url)
    uri.query = URI.encode_www_form(params)
    resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
    return JSON.parse(resp.body) if resp.is_a?(Net::HTTPSuccess)

    # Detect quota exhaustion (403 with quotaExceeded reason)
    if resp.code.to_i == 403
      body = JSON.parse(resp.body) rescue {}
      reason = body.dig("error", "errors", 0, "reason")
      if reason == "quotaExceeded" || reason == "dailyLimitExceeded"
        Rails.logger.warn("CameraRefreshService: YouTube API quota exhausted — skipping for #{YOUTUBE_QUOTA_COOLDOWN}")
        return { quota_exceeded: true }
      end
    end

    {}
  rescue => e
    Rails.logger.warn("CameraRefreshService youtube_json: #{e.message}")
    {}
  end

  def youtube_quota_exhausted?
    Rails.cache.read("youtube_api_quota_exhausted").present?
  end

  def mark_youtube_quota_exhausted!
    Rails.cache.write("youtube_api_quota_exhausted", true, expires_in: YOUTUBE_QUOTA_COOLDOWN)
  end

  # ── NYC DOT ───────────────────────────────────────────────

  def fetch_nyc_dot
    uri = URI("https://webcams.nyctmc.org/api/cameras")
    resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
    return [] unless resp.is_a?(Net::HTTPSuccess)

    cameras = JSON.parse(resp.body)
    cameras.filter_map do |cam|
      lat = cam["latitude"]&.to_f
      lng = cam["longitude"]&.to_f
      next unless lat && lng
      next unless lat.between?(@south, @north) && lng.between?(@west, @east)
      next if cam["isOnline"].to_s == "false"

      {
        webcam_id:   "nycdot-#{cam['id']}",
        source:      "nycdot",
        title:       cam["name"] || "NYC Traffic Cam",
        latitude:    lat,
        longitude:   lng,
        camera_type: "live",
        is_live:     true,
        player_url:  nil,
        image_url:   cam["imageUrl"] || "https://webcams.nyctmc.org/api/cameras/#{cam['id']}/image",
        preview_url: cam["imageUrl"] || "https://webcams.nyctmc.org/api/cameras/#{cam['id']}/image",
        city:        "New York",
        region:      cam["area"] || "NYC",
        country:     "United States",
        metadata:    {},
      }
    end
  rescue StandardError => e
    Rails.logger.warn("CameraRefreshService NYC DOT: #{e.message}")
    []
  end

  def bbox_overlaps_nyc?
    @north >= 40.4 && @south <= 40.95 && @east >= -74.3 && @west <= -73.7
  end

  # ── Staleness recheck ─────────────────────────────────────

  def self.recheck_stale_cameras(limit: 100)
    stale = Camera.stale.where(status: "active").order(:expires_at).limit(limit)
    stale.find_each do |cam|
      cam.update_columns(status: "expired", last_checked_at: Time.current)
    end

    # Group expired cameras by source & approximate region for batch re-fetching
    expired_by_region = Camera.expired.group_by { |c| "#{c.latitude.round},#{c.longitude.round}" }
    expired_by_region.each do |_cell, cams|
      lats = cams.map(&:latitude)
      lngs = cams.map(&:longitude)
      new(
        north: lats.max + 0.5, south: lats.min - 0.5,
        east: lngs.max + 0.5, west: lngs.min - 0.5,
      ).refresh
    end
  end
end
