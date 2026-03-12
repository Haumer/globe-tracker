class PositionSnapshot < ApplicationRecord
  scope :flights, -> { where(entity_type: "flight") }
  scope :ships, -> { where(entity_type: "ship") }
  scope :in_range, ->(from, to) { where(recorded_at: from..to) }
  scope :within_bounds, ->(bounds) {
    if bounds.present? && bounds.size >= 4
      where(latitude: bounds[:lamin]..bounds[:lamax],
            longitude: bounds[:lomin]..bounds[:lomax])
    else
      all
    end
  }

  MAX_PLAYBACK_ENTITIES = 2000

  # Returns snapshots grouped into time buckets for efficient playback.
  # Caps to MAX_PLAYBACK_ENTITIES unique entities to keep response size manageable.
  def self.playback_frames(entity_type:, from:, to:, bounds: {}, interval: 30)
    # First, find which entities to include (capped)
    entity_ids = where(entity_type: entity_type)
      .in_range(from, to)
      .within_bounds(bounds)
      .select(:entity_id).distinct
      .limit(MAX_PLAYBACK_ENTITIES)
      .pluck(:entity_id)

    return {} if entity_ids.empty?

    # Fetch snapshots only for selected entities, ordered for grouping
    snaps = where(entity_type: entity_type, entity_id: entity_ids)
      .in_range(from, to)
      .order(:recorded_at)

    # Group by time bucket
    snaps.group_by { |s| (s.recorded_at.to_i / interval) * interval }
         .transform_keys { |t| Time.at(t).utc.iso8601 }
         .transform_values { |bucket_snaps|
           # Keep only the latest snapshot per entity in each bucket
           bucket_snaps.group_by(&:entity_id)
                       .values
                       .map(&:last)
         }
  end

  # Purge snapshots older than retention period
  def self.purge_older_than(duration = 24.hours)
    where("recorded_at < ?", duration.ago).delete_all
  end
end
