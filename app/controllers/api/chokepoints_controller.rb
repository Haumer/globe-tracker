module Api
  class ChokepointsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      chokepoints = ChokepointMonitorService.analyze
      render json: { chokepoints: chokepoints, count: chokepoints.size }
    end
  end
end
