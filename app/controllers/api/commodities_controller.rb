module Api
  class CommoditiesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      quotes = latest_quotes_scope

      category = params[:category]
      quotes = quotes.where(category: category) if category.present?
      quotes = params[:at].present? ? quotes.to_a : YahooMarketSignalService.merge_quotes(quotes.to_a)

      spatial_quotes, watchlist_quotes = quotes.partition { |quote| quote.latitude.present? && quote.longitude.present? }
      watchlist_order = (YahooMarketSignalService.order_symbols + CommodityPriceService::WATCHLIST_SYMBOLS).uniq.each_with_index.to_h

      render json: {
        prices: spatial_quotes.sort_by { |quote| [quote.category.to_s, quote.symbol.to_s] }.map { |quote| serialize_quote(quote) },
        benchmarks: watchlist_quotes.sort_by { |quote| [watchlist_order.fetch(quote.symbol, 999), quote.category.to_s, quote.symbol.to_s] }.map { |quote| serialize_quote(quote) },
      }
    end

    private

    def latest_quotes_scope
      at = parse_time(params[:at])
      scope = CommodityPrice.all
      scope = scope.where("recorded_at <= ?", at) if at
      scope.select("DISTINCT ON (symbol) *").order(:symbol, recorded_at: :desc)
    end

    def parse_time(value)
      return nil if value.blank?

      Time.parse(value)
    rescue ArgumentError
      nil
    end

    def serialize_quote(quote)
      {
        symbol: quote.symbol,
        category: quote.category,
        name: quote.name,
        price: quote.price.to_f,
        change_pct: quote.change_pct&.to_f,
        unit: quote.unit,
        lat: quote.latitude,
        lng: quote.longitude,
        region: quote.region,
        recorded_at: quote.recorded_at&.iso8601,
        source: quote.respond_to?(:source) ? quote.source : "persisted",
        live_signal: quote.respond_to?(:live_signal) ? quote.live_signal : false,
      }
    end
  end
end
