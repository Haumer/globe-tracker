class ConflictEvent < ApplicationRecord
  include BoundsFilterable

  has_many :timeline_events, as: :eventable, dependent: :destroy

  # 1 = state-based, 2 = non-state, 3 = one-sided violence
  VIOLENCE_TYPES = { 1 => "State-based", 2 => "Non-state", 3 => "One-sided" }.freeze

  scope :recent, -> { where("date_start > ?", 1.year.ago) }
  scope :in_range, ->(from, to) { where(date_start: from..to) }

  def violence_label
    VIOLENCE_TYPES[type_of_violence] || "Unknown"
  end
end
