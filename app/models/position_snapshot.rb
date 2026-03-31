class PositionSnapshot < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  time_range_column :recorded_at

  scope :flights, -> { where(entity_type: "flight") }
  scope :ships, -> { where(entity_type: "ship") }

  MAX_PLAYBACK_ENTITIES = 2000

  def self.playback_frames(entity_type:, from:, to:, bounds: {}, interval: 30.minutes.to_i)
    scope = where(entity_type: entity_type)
      .in_range(from, to)
      .within_bounds(bounds)

    entity_ids = scope
      .select("entity_id, MAX(recorded_at) AS last_seen_at")
      .group(:entity_id)
      .order(Arel.sql("MAX(recorded_at) DESC"))
      .limit(MAX_PLAYBACK_ENTITIES)
      .pluck(:entity_id)

    return {} if entity_ids.empty?

    interval_seconds = interval.to_i.clamp(1, 7.days.to_i)

    snaps = scope.where(entity_id: entity_ids)
      .order(:recorded_at)

    snaps.group_by { |s| (s.recorded_at.to_i / interval_seconds) * interval_seconds }
         .transform_keys { |t| Time.at(t).utc.iso8601 }
         .transform_values { |bucket_snaps|
           bucket_snaps.group_by(&:entity_id).values.map(&:last)
         }
  end

  def self.purge_older_than(duration = 24.hours)
    where("recorded_at < ?", duration.ago).delete_all
  end
end
