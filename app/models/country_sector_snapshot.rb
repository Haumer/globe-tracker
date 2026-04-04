class CountrySectorSnapshot < ApplicationRecord
  validates :country_code_alpha3, :country_name, :sector_key, :sector_name,
    :metric_key, :metric_name, :period_year, :source, :dataset, presence: true

  scope :latest_first, -> { order(period_year: :desc, country_code_alpha3: :asc, sector_key: :asc) }
end
