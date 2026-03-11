class TimelineEvent < ApplicationRecord
  belongs_to :eventable, polymorphic: true

  scope :in_range, ->(from, to) { where(recorded_at: from..to) }
  scope :of_type, ->(*types) { where(event_type: types.flatten) }
  scope :within_bounds, ->(bounds) {
    if bounds.present? && bounds.size >= 4
      where(latitude: bounds[:lamin]..bounds[:lamax],
            longitude: bounds[:lomin]..bounds[:lomax])
    else
      all
    end
  }
end
