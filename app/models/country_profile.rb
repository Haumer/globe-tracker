class CountryProfile < ApplicationRecord
  validates :country_code_alpha3, :country_name, presence: true
end
