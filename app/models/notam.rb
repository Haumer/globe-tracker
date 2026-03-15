class Notam < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy

  time_range_column :effective_start, recent: 48.hours

  scope :active, -> { where("effective_end IS NULL OR effective_end > ?", Time.current) }
end
