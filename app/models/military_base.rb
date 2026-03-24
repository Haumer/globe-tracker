class MilitaryBase < ApplicationRecord
  include BoundsFilterable

  TYPES = %w[army navy air_force nuclear missile training logistics other].freeze

  scope :in_bbox, ->(north:, south:, east:, west:) {
    where(latitude: south..north, longitude: west..east)
  }
end
