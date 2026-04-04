module Api
  class ShippingLanesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      unless LayerAvailability.enabled?(:shipping_lanes)
        return render json: { shipping_lanes: [], shipping_corridors: [] }
      end

      render json: {
        shipping_lanes: ShippingLaneMapService.lanes,
        shipping_corridors: ShippingLaneMapService.corridors,
      }
    end
  end
end
