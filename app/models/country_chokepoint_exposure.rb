class CountryChokepointExposure < ApplicationRecord
  validates :country_code_alpha3, :country_name, :commodity_key, :chokepoint_key, :chokepoint_name, presence: true
end
