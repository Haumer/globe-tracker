class TradeFlowSnapshot < ApplicationRecord
  validates :reporter_country_code_alpha3, :partner_country_code_alpha3, :flow_direction,
    :commodity_key, :period_type, :period_start, :source, :dataset, presence: true

  scope :latest_first, -> { order(period_start: :desc, trade_value_usd: :desc) }
end
