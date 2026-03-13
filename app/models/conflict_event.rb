class ConflictEvent < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy

  VIOLENCE_TYPES = { 1 => "State-based", 2 => "Non-state", 3 => "One-sided" }.freeze

  time_range_column :date_start, recent: 1.year

  def violence_label
    VIOLENCE_TYPES[type_of_violence] || "Unknown"
  end
end
