class CountryCommodityDependency < ApplicationRecord
  validates :country_code_alpha3, :country_name, :commodity_key, presence: true
end
