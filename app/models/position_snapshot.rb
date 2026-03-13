class PositionSnapshot < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  time_range_column :recorded_at

  scope :flights, -> { where(entity_type: "flight") }
  scope :ships, -> { where(entity_type: "ship") }

  MAX_PLAYBACK_ENTITIES = 2000

  def self.playback_frames(entity_type:, from:, to:, bounds: {}, interval: 30)
    entity_ids = where(entity_type: entity_type)
      .in_range(from, to)
      .within_bounds(bounds)
      .select(:entity_id).distinct
      .limit(MAX_PLAYBACK_ENTITIES)
      .pluck(:entity_id)

    return {} if entity_ids.empty?

    snaps = where(entity_type: entity_type, entity_id: entity_ids)
      .in_range(from, to)
      .order(:recorded_at)

    snaps.group_by { |s| (s.recorded_at.to_i / interval) * interval }
         .transform_keys { |t| Time.at(t).utc.iso8601 }
         .transform_values { |bucket_snaps|
           bucket_snaps.group_by(&:entity_id).values.map(&:last)
         }
  end

  def self.purge_older_than(duration = 24.hours)
    where("recorded_at < ?", duration.ago).delete_all
  end
end
