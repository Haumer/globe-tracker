class NewsEvent < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  belongs_to :news_ingest, optional: true
  belongs_to :news_source, optional: true
  belongs_to :news_article, optional: true
  has_many :timeline_events, as: :eventable, dependent: :destroy

  time_range_column :published_at, recent: 24.hours
  scope :recent, -> { where("fetched_at > ?", 24.hours.ago) }
end
