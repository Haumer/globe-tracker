class Earthquake < ApplicationRecord
  include BoundsFilterable

  has_many :timeline_events, as: :eventable, dependent: :destroy

  scope :recent, -> { where("event_time > ?", 24.hours.ago) }
  scope :on_date, ->(date) { where(event_time: date.beginning_of_day..date.end_of_day) }
  scope :in_range, ->(from, to) { where(event_time: from..to) }
end
