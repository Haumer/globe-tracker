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

  # Keeps Unicode letters instead of transliterating them away.
  #
  # I18n.transliterate maps anything it has no Latin rule for to "?", so every
  # non-Latin script collapsed to an empty string: "Κόρινθος", "Харків" and
  # "القاهرة" all normalized to "". Titles from Greek, Cyrillic, Arabic, Hebrew
  # and CJK publishers -- 29% of the publisher registry -- could therefore
  # never match a place, and silently fell through to publisher-country
  # geocoding. Preserving the script lets a Greek headline match a Greek alias.
  #
  # Latin text is unaffected: it was already alphanumeric, so it normalizes
  # exactly as before and stored values stay valid.
  def self.normalize_name(value)
    value.to_s
      .unicode_normalize(:nfkc)
      .downcase
      .gsub(/[^[[:alnum:]]]+/, " ")
      .squish
  rescue ArgumentError, Encoding::CompatibilityError
    # Invalid encoding: fall back to a scrubbed ASCII pass rather than raise.
    value.to_s.scrub("").downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  # Latin-alphabet form, so "Köln" is also reachable as "koln" and "Zürich" as
  # "zurich". Stored alongside the native form as a separate alias.
  def self.ascii_name(value)
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
