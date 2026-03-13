class InternetOutage < ApplicationRecord
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy

  time_range_column :started_at, recent: 24.hours
end
