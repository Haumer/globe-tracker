class Earthquake < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy

  time_range_column :event_time, recent: 24.hours
end
