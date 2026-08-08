class FireCluster < ApplicationRecord
  include BoundsFilterable

  has_many :fire_observations, dependent: :delete_all
  has_many :timeline_events, as: :eventable, dependent: :destroy

  # Fire Radiative Power in megawatts -- a physical measure of radiative energy
  # release, so the bands mean something rather than being an invented score.
  # Roughly an order of magnitude apart, landing on natural breaks in the data:
  # a sub-10 MW single-pixel detection is almost always agricultural burning or
  # a gas flare, while >1000 MW is a major complex.
  TIERS = {
    "minor" => 0.0,
    "moderate" => 10.0,
    "major" => 100.0,
    "extreme" => 1000.0,
  }.freeze

  DISCRETE_TIERS = %w[major extreme].freeze

  scope :by_tier, ->(tier) { tier.present? ? where(tier: tier) : all }
  scope :notable, -> { where(tier: DISCRETE_TIERS) }
  scope :burning_at, ->(time) { where(first_detected_at: ..time).where(last_detected_at: time..) }
  scope :strongest, -> { order(intensity_mw: :desc) }

  # Whether a fire is growing or dying, judged only against passes by the SAME
  # instrument. MODIS resolves 1km pixels and VIIRS 375m, so a MODIS pass
  # following a VIIRS peak reads as collapse when nothing has changed on the
  # ground -- the largest fire in the feed was mislabelled "dying" that way
  # while its footprint grew from 45 to 1,424 pixels.
  def trend
    points = fire_observations.chronological.to_a
    latest = points.last
    return "unknown" if latest.nil?

    comparable = points.select { |point| point.instrument == latest.instrument }
    return "unknown" if comparable.size < 2

    peak = comparable.map(&:frp_mw).max.to_f
    return "unknown" if peak <= 0

    ratio = latest.frp_mw.to_f / peak
    return "growing" if ratio >= 0.9
    return "easing" if ratio >= 0.4

    "dying"
  end

  def series
    FireObservation.series_for(self)
  end

  def self.tier_for(intensity_mw)
    mw = intensity_mw.to_f
    return "extreme" if mw >= TIERS["extreme"]
    return "major" if mw >= TIERS["major"]
    return "moderate" if mw >= TIERS["moderate"]

    "minor"
  end
end
