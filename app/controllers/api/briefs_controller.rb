module Api
  class BriefsController < ApplicationController
    skip_before_action :authenticate_user!
    before_action :require_admin_api!

    def show
      brief = Rails.cache.read(IntelligenceBriefService::CACHE_KEY)

      if brief
        expires_in 30.minutes, public: true
        render json: brief
      else
        # Generate on first request (cached for 6 hours after)
        GenerateBriefJob.perform_later unless Rails.cache.read("brief_generating")
        Rails.cache.write("brief_generating", true, expires_in: 2.minutes)
        render json: { status: "generating", message: "Intelligence brief is being generated. Check back in ~30 seconds." }
      end
    end

    private

    def require_admin_api!
      return if current_user&.admin?

      render json: { error: "Not authorized" }, status: :forbidden
    end
  end
end
