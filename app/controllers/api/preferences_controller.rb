module Api
  class PreferencesController < ApplicationController
    before_action :authenticate_user!

    def show
      render json: current_user.preferences || {}
    end

    def update
      current_user.update!(preferences: current_user.preferences.merge(preference_params))
      head :ok
    end

    private

    def preference_params
      params.permit(
        :camera_lat, :camera_lng, :camera_height, :camera_heading, :camera_pitch,
        :sidebar_collapsed,
        layers: {},
        selected_countries: [],
        airline_filter: [],
        open_sections: []
      ).to_h
    end
  end
end
