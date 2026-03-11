class SatelliteTleSnapshot < ApplicationRecord
  scope :for_time, ->(time) { where("recorded_at <= ?", time).order(recorded_at: :desc) }

  # Returns the most recent TLE set before the given time, one per norad_id
  def self.tles_at(time)
    where("recorded_at <= ?", time)
      .select("DISTINCT ON (norad_id) norad_id, name, tle_line1, tle_line2, category, recorded_at")
      .order(:norad_id, recorded_at: :desc)
  end

  def self.purge_older_than(duration = 7.days)
    where("recorded_at < ?", duration.ago).delete_all
  end
end
