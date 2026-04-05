class GeoconfirmedEvent < ApplicationRecord
  include BoundsFilterable

  validates :external_id, :map_region, :latitude, :longitude, :fetched_at, presence: true

  scope :recent, -> { where("event_time > ?", 30.days.ago) }
  scope :for_region, ->(region) { where(map_region: region) }
end
