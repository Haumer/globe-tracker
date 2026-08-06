class GeoconfirmedEvent < ApplicationRecord
  include BoundsFilterable

  has_many :timeline_events, as: :eventable, dependent: :destroy

  validates :external_id, :map_region, :latitude, :longitude, :fetched_at, presence: true

  # Tracks the retention window rather than a fixed 30 days — asking for more
  # history than PurgeStaleDataJob keeps just returns a silently short answer.
  scope :recent, -> { where(event_time: DataRetention.cutoff..) }
  scope :for_region, ->(region) { where(map_region: region) }

  def timeline_recorded_at
    posted_at || event_time || fetched_at
  end
end
