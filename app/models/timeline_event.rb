class TimelineEvent < ApplicationRecord
  include BoundsFilterable
  include TimeRangeQueries

  belongs_to :eventable, polymorphic: true

  time_range_column :recorded_at
  scope :of_type, ->(*types) { where(event_type: types.flatten) }
end
