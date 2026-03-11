class GpsJammingSnapshot < ApplicationRecord
  has_many :timeline_events, as: :eventable, dependent: :destroy

  scope :recent, -> { where("recorded_at > ?", 1.hour.ago) }
  scope :on_date, ->(date) { where(recorded_at: date.beginning_of_day..date.end_of_day) }
  scope :in_range, ->(from, to) { where(recorded_at: from..to) }
end
