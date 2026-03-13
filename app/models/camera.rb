class Camera < ApplicationRecord
  include BoundsFilterable

  SOURCES = %w[windy youtube nycdot].freeze
  STATUSES = %w[active expired dead].freeze

  # Staleness tiers per source
  STALE_AFTER = {
    "youtube" => 3.hours,
    "nycdot"  => 30.days,
    "windy"   => 30.days,
  }.freeze

  scope :active,  -> { where(status: "active") }
  scope :expired, -> { where(status: "expired") }
  scope :alive,   -> { where.not(status: "dead") }  # active + expired (still show to user)
  scope :stale,   -> { where("expires_at < ?", Time.current) }
  scope :fresh,   -> { where("expires_at >= ?", Time.current) }
  scope :by_source, ->(src) { where(source: src) if src.present? }

  scope :in_bbox, ->(north:, south:, east:, west:) {
    where(latitude: south..north, longitude: west..east)
  }

  validates :webcam_id, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }

  def stale?
    expires_at.present? && expires_at < Time.current
  end

  def mark_checked!
    update_columns(last_checked_at: Time.current)
  end

  def refresh_expiry!
    ttl = STALE_AFTER[source] || 30.days
    update_columns(expires_at: Time.current + ttl, status: "active")
  end
end
