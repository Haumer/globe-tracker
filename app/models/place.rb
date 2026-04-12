class Place < ApplicationRecord
  has_many :place_aliases, dependent: :delete_all

  validates :canonical_key, :name, :normalized_name, :place_type, :source, presence: true
  validates :canonical_key, uniqueness: true
  validates :latitude, :longitude, presence: true

  before_validation :set_normalized_name

  scope :ranked, -> {
    order(Arel.sql("CASE WHEN country_code IS NULL THEN 0 ELSE 1 END DESC"), importance_score: :desc, name: :asc)
  }

  def self.lookup(name, country_code: nil)
    normalized = normalize_name(name)
    return none if normalized.blank?

    matching_ids = left_outer_joins(:place_aliases)
      .where("places.normalized_name = :name OR place_aliases.normalized_name = :name", name: normalized)
      .select(:id)
    scope = where(id: matching_ids)
    scope = scope.where(country_code: [country_code, nil]) if country_code.present?
    scope.ranked
  end

  def self.normalize_name(value)
    I18n.transliterate(value.to_s)
      .downcase
      .gsub(/[^a-z0-9]+/, " ")
      .squish
  end

  private

  def set_normalized_name
    self.normalized_name = self.class.normalize_name(name)
  end
end
