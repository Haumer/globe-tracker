class FireObservation < ApplicationRecord
  belongs_to :fire_cluster

  scope :chronological, -> { order(:acq_datetime) }

  # The evolution series: one point per satellite pass, attributed to the
  # platform that saw it. p99 is 6 passes, so these stay small.
  def self.series_for(fire_cluster)
    chronological.where(fire_cluster: fire_cluster).map do |observation|
      {
        at: observation.acq_datetime,
        mw: observation.frp_mw,
        pixels: observation.pixel_count,
        satellite: observation.satellite,
        instrument: observation.instrument,
      }
    end
  end
end
