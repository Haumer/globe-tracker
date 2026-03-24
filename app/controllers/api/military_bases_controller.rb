module Api
  class MilitaryBasesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      bases = MilitaryBase.all

      if params[:north].present? && params[:south].present? &&
         params[:east].present? && params[:west].present?
        bases = bases.in_bbox(
          north: params[:north].to_f,
          south: params[:south].to_f,
          east: params[:east].to_f,
          west: params[:west].to_f,
        )
      end

      # Prioritize: named bases first, then by strategic importance
      bases = bases.order(
        Arel.sql("CASE WHEN name IS NOT NULL AND name != '' THEN 0 ELSE 1 END"),
        Arel.sql("CASE base_type
          WHEN 'nuclear' THEN 0 WHEN 'missile' THEN 1 WHEN 'air_force' THEN 2
          WHEN 'navy' THEN 3 WHEN 'army' THEN 4 WHEN 'logistics' THEN 5
          WHEN 'training' THEN 6 ELSE 7 END"),
      ).limit(500)

      data = bases.map { |b|
        [b.id, b.latitude, b.longitude, b.name, b.base_type, b.country, b.operator]
      }

      if data.empty?
        expires_in 30.seconds, public: true
      else
        max_updated = MilitaryBase.maximum(:updated_at)&.to_i || 0
        response.headers["ETag"] = Digest::MD5.hexdigest("mb:#{data.size}:#{max_updated}")
        expires_in 1.hour, public: true
      end

      render json: data
    end
  end
end
