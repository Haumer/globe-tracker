class FireHotspot < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy

  time_range_column :acq_datetime, recent: 48.hours

  SATELLITE_NORAD = {
    "Suomi NPP" => 37849,
    "NOAA-20" => 43013,
    "NOAA-21" => 54234,
    "Terra" => 25994,
    "Aqua" => 27424,
  }.freeze
end
