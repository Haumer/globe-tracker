module Api
  class TheaterBriefsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      payload = TheaterBriefService.fetch_or_enqueue(
        theater: params[:theater],
        cell_key: params[:cell_key]
      )
      return render json: { status: "unavailable" }, status: :not_found unless payload

      render json: payload
    end
  end
end
