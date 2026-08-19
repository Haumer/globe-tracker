module Api
  class SituationLayersController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      plan = SituationLayerPlanService.call(situation_id: params[:id].to_i)
      return head :not_found unless plan

      expires_in 2.minutes, public: true
      render json: plan
    end
  end
end
