class AreaWorkspace < ApplicationRecord
  SCOPE_TYPES = %w[bbox country_set preset_region].freeze
  PROFILES = %w[general land_conflict maritime airspace infrastructure cyber].freeze

  belongs_to :user

  validates :name, presence: true, length: { maximum: 120 }
  validates :scope_type, presence: true, inclusion: { in: SCOPE_TYPES }
  validates :profile, presence: true, inclusion: { in: PROFILES }
  validate :validate_bounds_shape

  scope :recent, -> { order(updated_at: :desc, created_at: :desc) }

  before_validation :normalize_json_fields

  def bounds_hash
    (bounds || {}).with_indifferent_access.slice(:lamin, :lamax, :lomin, :lomax).transform_values(&:to_f)
  end

  def country_names
    Array(scope_metadata_value(:countries)).map(&:to_s)
  end

  def region_name
    scope_metadata_value(:region_name).presence
  end

  def region_key
    scope_metadata_value(:region_key).presence
  end

  def scope_label
    case scope_type
    when "preset_region" then "Preset Region"
    when "country_set" then "Country Selection"
    when "bbox" then "Custom Area"
    else scope_type.to_s.humanize
    end
  end

  def scope_detail
    case scope_type
    when "preset_region"
      scope_metadata_value(:description).presence || "Curated regional monitor from the globe."
    when "country_set"
      count = country_names.size
      return "Saved from 1 selected country." if count == 1
      return "Saved from #{count} selected countries." if count.positive?

      "Saved from a country-scoped globe selection."
    when "bbox"
      radius_km = scope_metadata_value(:radius_km).to_i
      return "Drawn circle with a #{radius_km} km radius." if radius_km.positive?

      "Saved from a custom globe area."
    else
      "Saved from the globe."
    end
  end

  def profile_label
    profile.to_s.tr("_", " ").titleize
  end

  def layer_labels
    Array(default_layers).filter_map do |layer|
      next if layer.blank?

      layer.to_s.gsub(/([a-z])([A-Z])/, '\1 \2').tr("_", " ").titleize
    end
  end

  def bounds_label
    return "Unavailable" if bounds_hash.blank?

    format("%.2f to %.2f lat · %.2f to %.2f lon", bounds_hash[:lamin], bounds_hash[:lamax], bounds_hash[:lomin], bounds_hash[:lomax])
  end

  private

  def normalize_json_fields
    self.bounds = (bounds || {}).deep_stringify_keys
    self.scope_metadata = (scope_metadata || {}).deep_stringify_keys
    self.default_layers = Array(default_layers).map(&:to_s).reject(&:blank?).uniq
  end

  def validate_bounds_shape
    value = bounds_hash
    required = %i[lamin lamax lomin lomax]
    missing = required.reject { |key| value.key?(key) }
    if missing.any?
      errors.add(:bounds, "must include #{missing.join(', ')}")
      return
    end

    return if value[:lamin] <= value[:lamax] && value[:lomin] <= value[:lomax]

    errors.add(:bounds, "must define a valid bounding box")
  end

  def scope_metadata_value(key)
    (scope_metadata || {}).with_indifferent_access[key]
  end
end
