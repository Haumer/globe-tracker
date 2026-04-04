class ShippingLaneMapService
  module RouteMethods
    private

    def route_points_for(anchors)
      ShippingLaneMapService::CorridorGraph.route_points_for(anchors)
    end
  end
end
