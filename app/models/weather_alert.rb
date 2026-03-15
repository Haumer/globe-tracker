class WeatherAlert < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy

  time_range_column :onset, recent: 48.hours

  scope :active, -> { where("expires IS NULL OR expires > ?", Time.current) }
end
