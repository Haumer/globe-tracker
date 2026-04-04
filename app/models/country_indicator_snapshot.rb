class CountryIndicatorSnapshot < ApplicationRecord
  validates :country_code_alpha3, :country_name, :indicator_key, :indicator_name,
    :period_type, :period_start, :source, :dataset, presence: true

  scope :latest_first, -> { order(period_start: :desc, country_code_alpha3: :asc, indicator_key: :asc) }
end
