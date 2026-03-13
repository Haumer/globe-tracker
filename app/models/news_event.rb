class NewsEvent < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy

  time_range_column :published_at, recent: 24.hours
  scope :recent, -> { where("fetched_at > ?", 24.hours.ago) }
end
