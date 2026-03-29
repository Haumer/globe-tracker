class CommodityPrice < ApplicationRecord
  CATEGORIES = %w[commodity currency index rate crypto].freeze

  validates :symbol, presence: true
  validates :category, inclusion: { in: CATEGORIES }

  scope :latest, -> { where("recorded_at = (SELECT MAX(recorded_at) FROM commodity_prices cp2 WHERE cp2.symbol = commodity_prices.symbol)") }
  scope :commodities, -> { where(category: "commodity") }
  scope :currencies, -> { where(category: "currency") }
  scope :spatial, -> { where.not(latitude: nil, longitude: nil) }
  scope :watchlist, -> { where(latitude: nil, longitude: nil) }
end
