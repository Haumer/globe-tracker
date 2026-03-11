class PowerPlant < ApplicationRecord
  include BoundsFilterable

  FUEL_TYPES = %w[Coal Gas Oil Nuclear Hydro Solar Wind Biomass Geothermal Waste Petcoke Cogeneration Storage Other].freeze

  scope :by_fuel, ->(fuel) { where(primary_fuel: fuel) if fuel.present? }
end
