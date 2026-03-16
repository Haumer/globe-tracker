module Api
  class CommoditiesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      # Get latest price for each symbol
      prices = CommodityPrice.select("DISTINCT ON (symbol) *").order(:symbol, recorded_at: :desc)

      category = params[:category]
      prices = prices.where(category: category) if category.present?

      render json: {
        prices: prices.map { |p|
          {
            symbol: p.symbol,
            category: p.category,
            name: p.name,
            price: p.price.to_f,
            change_pct: p.change_pct&.to_f,
            unit: p.unit,
            lat: p.latitude,
            lng: p.longitude,
            region: p.region,
            recorded_at: p.recorded_at&.iso8601,
          }
        },
      }
    end
  end
end
