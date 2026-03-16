module Api
  class InternetTrafficController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      snapshots = InternetTrafficSnapshot.latest_batch

      traffic = snapshots.map do |s|
        {
          code: s.country_code,
          name: s.country_name,
          traffic: s.traffic_pct,
          attack_origin: s.attack_origin_pct,
          attack_target: s.attack_target_pct,
        }
      end

      pairs = CloudflareRadarService.cached_attack_pairs

      render json: {
        traffic: traffic,
        attack_pairs: pairs.map { |p|
          { origin: p[:origin], target: p[:target], origin_name: p[:origin_name], target_name: p[:target_name], pct: p[:pct] }
        },
        recorded_at: snapshots.first&.recorded_at&.iso8601,
      }
    end
  end
end
