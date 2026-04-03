module Api
  class ShippingLanesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      render json: {
        shipping_lanes: ShippingLaneMapService.lanes,
        shipping_corridors: ShippingLaneMapService.corridors,
      }
    end
  end
end
