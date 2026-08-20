module Api
  class SituationsController < ApplicationController
    skip_before_action :authenticate_user!

    DEFAULT_DAYS = SituationBuilder::WINDOW_DAYS
    MAX_DAYS = 90

    def index
      render json: SituationBoardService.call(days: window_days)
    end

    # The admin-1 region containing each situation's anchor, deduped -- Hamas
    # and Gaza both resolve to the Gaza Strip and should draw it once. The
    # board uses these to replace nominal circles with real shapes; anchors no
    # region contains (sea anchors, unresolvable coordinates) are absent and
    # keep their dot.
    def regions
      situations = SituationBoardService.call(days: window_days)[:situations] || []
      anchors = situations.filter_map do |situation|
        anchor = situation[:anchor]
        next unless anchor
        { id: situation[:id], lat: anchor[:lat], lng: anchor[:lng] }
      end

      features = AnchorRegionService.features_for(anchors)
        .group_by { |_id, feature| feature["properties"].values_at("name", "country_code") }
        .map do |_key, entries|
          feature = entries.first.last
          feature.merge("properties" => feature["properties"].merge(
            "situation_ids" => entries.map(&:first).sort
          ))
        end

      expires_in 5.minutes, public: true
      render json: { "type" => "FeatureCollection", "features" => features }
    end

    private

    def window_days
      requested = params[:days].to_i
      return DEFAULT_DAYS unless requested.positive?

      [requested, MAX_DAYS].min
    end
  end
end
