class Airport < ApplicationRecord
  include BoundsFilterable

  AIRPORT_TYPES = %w[large_airport medium_airport military].freeze

  MILITARY_KEYWORDS = [
    "Air Force", "AFB", "Military", "Army", "Navy", "Naval", "Marine",
    "RAF ", "RAAF", "Fliegerhorst", "Base Aérienne", "Luftwaffe",
    "Air Base", "Air Station", "MCAS", "RNAS", "CFB", "PAF",
    "Karup", "Flyvestation", "Flugplatz"
  ].freeze

  scope :by_type, ->(type) { where(airport_type: type) if type.present? }
  scope :military, -> { where(is_military: true) }
  scope :civilian, -> { where(is_military: false) }
end
