module BoundsFilterable
  extend ActiveSupport::Concern

  included do
    scope :within_bounds, ->(bounds) {
      if bounds.present? && bounds.size >= 4
        where(latitude: bounds[:lamin]..bounds[:lamax],
              longitude: bounds[:lomin]..bounds[:lomax])
      else
        all
      end
    }
  end
end
