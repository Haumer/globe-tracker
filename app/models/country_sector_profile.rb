class CountrySectorProfile < ApplicationRecord
  validates :country_code_alpha3, :country_name, :sector_key, :sector_name, :period_year, presence: true
end
