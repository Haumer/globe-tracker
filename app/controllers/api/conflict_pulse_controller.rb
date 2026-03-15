module Api
  class ConflictPulseController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      zones = ConflictPulseService.analyze
      render json: { zones: zones, count: zones.size }
    end
  end
end
