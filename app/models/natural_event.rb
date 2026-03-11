class NaturalEvent < ApplicationRecord
  include BoundsFilterable

  has_many :timeline_events, as: :eventable, dependent: :destroy

  scope :recent, -> { where("fetched_at > ?", 24.hours.ago) }
  scope :on_date, ->(date) { where(fetched_at: date.beginning_of_day..date.end_of_day) }
  scope :in_range, ->(from, to) { where(event_date: from..to) }
end
