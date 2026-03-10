require "net/http"

module Api
  class WebcamsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      api_key = ENV["WINDY_API_KEY"]
      return render(json: { error: "WINDY_API_KEY not configured" }, status: :service_unavailable) unless api_key.present?

      limit = [(params[:limit]&.to_i || 50), 50].min

      # Prefer bounding box if provided, otherwise fall back to nearby
      if params[:north].present? && params[:south].present?
        north = params[:north].to_f
        east  = params[:east].to_f
        south = params[:south].to_f
        west  = params[:west].to_f
        query = "bbox=#{north},#{east},#{south},#{west}"
      elsif params[:lat].present? && params[:lng].present?
        lat = params[:lat].to_f
        lng = params[:lng].to_f
        radius = [(params[:radius]&.to_i || 50), 250].min
        query = "nearby=#{lat},#{lng},#{radius}"
      else
        return render(json: { error: "bbox or lat/lng required" }, status: :bad_request)
      end

      uri = URI("https://api.windy.com/webcams/api/v3/webcams?#{query}&limit=#{limit}&include=images,player,location")

      request = Net::HTTP::Get.new(uri)
      request["x-windy-api-key"] = api_key

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPSuccess)
        render json: response.body, content_type: "application/json"
      else
        render json: { error: "Windy API error", status: response.code }, status: :bad_gateway
      end
    end
  end
end
