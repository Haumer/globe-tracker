module Api
  class SituationsController < ApplicationController
    skip_before_action :authenticate_user!

    DEFAULT_DAYS = 21
    MAX_DAYS = 90

    def index
      render json: SituationBoardService.call(days: window_days)
    end

    private

    def window_days
      requested = params[:days].to_i
      return DEFAULT_DAYS unless requested.positive?

      [requested, MAX_DAYS].min
    end
  end
end
