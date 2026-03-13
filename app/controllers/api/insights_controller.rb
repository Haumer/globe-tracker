module Api
  class InsightsController < ApplicationController
    def index
      insights = Rails.cache.fetch("cross_layer_insights", expires_in: 5.minutes) do
        CrossLayerAnalyzer.analyze
      end

      render json: { insights: insights }
    end
  end
end
