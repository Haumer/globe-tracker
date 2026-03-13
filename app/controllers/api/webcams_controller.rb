module Api
  class WebcamsController < ApplicationController
    skip_before_action :authenticate_user!
    include BackgroundRefreshable

    def index
      north = params[:north]&.to_f
      south = params[:south]&.to_f
      east  = params[:east]&.to_f
      west  = params[:west]&.to_f

      unless params[:north].present? && params[:south].present? &&
             params[:east].present? && params[:west].present?
        return render(json: { error: "Bounding box required" }, status: :bad_request)
      end

      # 1. Return cached cameras from DB immediately
      max = (params[:limit]&.to_i || 50).clamp(1, 150)
      cameras = Camera.alive.in_bbox(north: north, south: south, east: east, west: west)
                       .order(Arel.sql("CASE source WHEN 'youtube' THEN 0 WHEN 'nycdot' THEN 0 ELSE CASE WHEN is_live THEN 1 ELSE 2 END END, fetched_at DESC"))
                       .limit(max)
      camera_records = cameras.to_a

      # 2. Enqueue background refresh if any cells are stale or unfetched
      has_stale = camera_records.any?(&:stale?) || camera_records.empty?
      if has_stale
        enqueue_background_refresh(
          RefreshCamerasJob,
          { north: north, south: south, east: east, west: west },
          key: "cameras:#{north.round(1)},#{south.round(1)},#{east.round(1)},#{west.round(1)}",
          debounce: 2.minutes,
        )
      end

      render json: {
        webcams: camera_records.map { |c| serialize_camera(c) },
        stale: has_stale,
        total: camera_records.size,
      }
    end

    private

    def serialize_camera(c)
      {
        "webcamId"      => c.webcam_id,
        "title"         => c.title,
        "source"        => c.source,
        "live"          => c.is_live,
        "location"      => {
          "latitude"  => c.latitude,
          "longitude" => c.longitude,
          "city"      => c.city,
          "region"    => c.region,
          "country"   => c.country,
        },
        "images"        => {
          "current" => {
            "preview" => c.image_url,
            "icon"    => c.preview_url,
          },
        },
        "player"        => c.player_url ? {
          "live" => { "available" => true, "embed" => c.player_url },
        } : nil,
        "videoId"       => c.video_id,
        "channelTitle"  => c.channel_title,
        "lastUpdatedOn" => c.fetched_at&.iso8601,
        "viewCount"     => c.view_count,
        "stale"         => c.stale?,
      }
    end
  end
end
