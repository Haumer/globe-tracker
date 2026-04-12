class PlaceAlias < ApplicationRecord
  belongs_to :place

  validates :name, :normalized_name, :alias_type, presence: true

  before_validation :set_normalized_name

  private

  def set_normalized_name
    self.normalized_name = Place.normalize_name(name)
  end
end
