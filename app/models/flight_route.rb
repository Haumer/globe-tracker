class FlightRoute < ApplicationRecord
  STATUSES = %w[pending fetched failed].freeze

  before_validation :normalize_callsign!

  validates :callsign, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :fresh, -> { where("expires_at > ?", Time.current) }

  def fresh?
    expires_at.present? && expires_at > Time.current
  end

  def available?
    status == "fetched" && route.present?
  end

  def pending?
    status == "pending"
  end

  def payload
    {
      callsign: callsign,
      route: route,
      operator_iata: operator_iata,
      flight_number: flight_number,
    }
  end

  private

  def normalize_callsign!
    self.callsign = self.class.normalize_callsign(callsign)
  end

  def self.normalize_callsign(value)
    value.to_s.strip.upcase.presence
  end
end
