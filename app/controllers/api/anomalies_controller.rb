module Api
  class AnomaliesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      anomalies = Rails.cache.fetch("anomalies", expires_in: 2.minutes) do
        AnomalyDetector.detect
      end
      render json: anomalies
    end
  end
end
