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

  # Returns snapshots grouped into time buckets for efficient playback
  # Each bucket contains all entity positions at that moment
  def self.playback_frames(entity_type:, from:, to:, bounds: {}, interval: 10)
    snaps = where(entity_type: entity_type).in_range(from, to).within_bounds(bounds)
                .order(:recorded_at)

    # Group by time bucket (rounded to interval seconds)
    snaps.group_by { |s| (s.recorded_at.to_i / interval) * interval }
         .transform_keys { |t| Time.at(t).utc.iso8601 }
  end

  # Purge snapshots older than retention period
  def self.purge_older_than(duration = 24.hours)
    where("recorded_at < ?", duration.ago).delete_all
  end
end
