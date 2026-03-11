class InternetOutage < ApplicationRecord
  has_many :timeline_events, as: :eventable, dependent: :destroy

  scope :recent, -> { where("started_at > ?", 24.hours.ago) }
  scope :on_date, ->(date) { where(started_at: date.beginning_of_day..date.end_of_day) }
  scope :in_range, ->(from, to) { where(started_at: from..to) }
end
