class GpsJammingSnapshot < ApplicationRecord
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy

  time_range_column :recorded_at, recent: 1.hour
end
