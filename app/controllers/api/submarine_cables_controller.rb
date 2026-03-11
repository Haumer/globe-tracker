module Api
  class SubmarineCablesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      enqueue_background_refresh(RefreshSubmarineCablesJob, key: "submarine-cables", debounce: 15.minutes) if SubmarineCableRefreshService.stale?

      cables = SubmarineCable.all
      render json: {
        cables: cables.map { |c|
          {
            id: c.cable_id,
            name: c.name,
            color: c.color,
            coordinates: c.coordinates,
          }
        },
        landingPoints: SubmarineCableRefreshService.cached_landing_points,
      }
    end
  end
end
