class FireHotspot < ApplicationRecord
  include BoundsFilterable

  has_many :timeline_events, as: :eventable, dependent: :destroy

  scope :recent, -> { where("acq_datetime > ?", 48.hours.ago) }
  scope :in_range, ->(from, to) { where(acq_datetime: from..to) }

  SATELLITE_NORAD = {
    "Suomi NPP" => 37849,
    "NOAA-20" => 43013,
    "NOAA-21" => 54234,
    "Terra" => 25994,
    "Aqua" => 27424,
  }.freeze
end
