module TimeRangeQueries
  extend ActiveSupport::Concern

  class_methods do
    # Declare which column powers the recent/in_range/on_date scopes.
    # Call once in each model: `time_range_column :event_time, recent: 24.hours`
    def time_range_column(column, recent: 24.hours)
      scope :recent,   -> { where("#{column} > ?", recent.ago) }
      scope :in_range,  ->(from, to) { where(column => from..to) }
      scope :on_date,   ->(date) { where(column => date.beginning_of_day..date.end_of_day) }
    end
  end
end
