module Api
  class TrendingController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      trends = TrendingKeywordTracker.trending(limit: 20)
      render json: trends
    end
  end
end
