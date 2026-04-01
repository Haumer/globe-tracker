class EnergyBalanceSnapshot < ApplicationRecord
  validates :country_code_alpha3, :country_name, :commodity_key, :metric_key,
    :period_type, :period_start, :source, :dataset, presence: true

  scope :latest_first, -> { order(period_start: :desc, country_code_alpha3: :asc, commodity_key: :asc) }
end
