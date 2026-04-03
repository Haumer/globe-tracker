module Api
  class PortsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      render json: {
        ports: PortMapService.ports,
      }
    end
  end
end
