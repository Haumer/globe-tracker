require "set"

class PlaceGazetteerSyncService
  extend Refreshable

  ALPHA3_TO_ALPHA2 = {
    "AUT" => "at",
    "CHE" => "ch",
    "DEU" => "de",
  }.freeze

  SEEDED_AMBIGUOUS_PLACES = [
    { key: "london-gb", name: "London", country_code: "gb", country_name: "United Kingdom", admin_area: "England", lat: 51.5074, lng: -0.1278, importance_score: 0.99, aliases: [] },
    { key: "london-ca", name: "London", country_code: "ca", country_name: "Canada", admin_area: "Ontario", lat: 42.9849, lng: -81.2453, importance_score: 0.55, aliases: ["London Ontario"] },
    { key: "paris-fr", name: "Paris", country_code: "fr", country_name: "France", admin_area: "Ile-de-France", lat: 48.8566, lng: 2.3522, importance_score: 0.98, aliases: [] },
    { key: "paris-us", name: "Paris", country_code: "us", country_name: "United States", admin_area: "Texas", lat: 33.6609, lng: -95.5555, importance_score: 0.35, aliases: ["Paris Texas"] },
    { key: "tripoli-ly", name: "Tripoli", country_code: "ly", country_name: "Libya", admin_area: nil, lat: 32.8872, lng: 13.1913, importance_score: 0.78, aliases: [] },
    { key: "tripoli-lb", name: "Tripoli", country_code: "lb", country_name: "Lebanon", admin_area: "North Governorate", lat: 34.4367, lng: 35.8497, importance_score: 0.58, aliases: ["Tripoli Lebanon"] },
  ].freeze

  refreshes model: Place, interval: 24.hours, column: :updated_at

  class << self
    def refresh
      new.refresh
    end
  end

  def refresh
    count = 0
    Place.transaction do
      count += sync_ambiguous_places
      count += sync_global_city_coords
      count += sync_regional_city_profiles
    end
    count
  end

  private

  def sync_ambiguous_places
    SEEDED_AMBIGUOUS_PLACES.sum do |attrs|
      upsert_place!(
        canonical_key: "place:seed:#{attrs.fetch(:key)}",
        name: attrs.fetch(:name),
        place_type: "city",
        country_code: attrs[:country_code],
        country_name: attrs[:country_name],
        admin_area: attrs[:admin_area],
        latitude: attrs.fetch(:lat),
        longitude: attrs.fetch(:lng),
        importance_score: attrs.fetch(:importance_score),
        source: "seeded_ambiguity",
        aliases: attrs[:aliases],
        metadata: { source_detail: "manual ambiguity guard" }
      )
    end
  end

  def sync_global_city_coords
    grouped = NewsGeocodable::CITY_COORDS.each_with_object({}) do |(name, coords), memo|
      key = "#{coords[0].round(4)},#{coords[1].round(4)}"
      memo[key] ||= { coords: coords, aliases: [] }
      memo[key][:aliases] << name
    end

    grouped.sum do |_coord_key, payload|
      aliases = payload.fetch(:aliases).uniq
      canonical_name = best_alias(aliases)
      lat, lng = payload.fetch(:coords)
      upsert_place!(
        canonical_key: "place:news-geocodable:#{canonical_name.parameterize}-#{lat.round(4)}-#{lng.round(4)}",
        name: canonical_name.titleize,
        place_type: infer_place_type(canonical_name),
        latitude: lat,
        longitude: lng,
        importance_score: global_importance_score(aliases),
        source: "news_geocodable",
        aliases: aliases,
        metadata: { alias_count: aliases.size }
      )
    end
  end

  def sync_regional_city_profiles
    RegionalCityProfileCatalog.all.sum do |record|
      country_code_alpha3 = record["country_code"].to_s.upcase.presence
      country_code = ALPHA3_TO_ALPHA2[country_code_alpha3] || country_code_alpha3&.downcase
      priority = record["priority"].to_i
      upsert_place!(
        canonical_key: "place:city-profile:#{record.fetch("id")}",
        name: record.fetch("name"),
        place_type: "city",
        country_code: country_code,
        country_name: record["country_name"],
        admin_area: record["admin_area"],
        latitude: record.fetch("lat"),
        longitude: record.fetch("lng"),
        importance_score: profile_importance_score(priority),
        source: "city_profile",
        aliases: record["aliases"],
        metadata: {
          country_code_alpha3: country_code_alpha3,
          priority: priority,
          role_tags: record["role_tags"],
          strategic_sectors: record["strategic_sectors"],
          source_pack: record["source_pack"],
          summary: record["summary"],
        }.compact
      )
    end
  end

  def upsert_place!(canonical_key:, name:, place_type:, latitude:, longitude:, source:, aliases: [], country_code: nil,
                    country_name: nil, admin_area: nil, importance_score: 0.0, metadata: {})
    place = Place.find_or_initialize_by(canonical_key: canonical_key)
    place.assign_attributes(
      name: name,
      normalized_name: Place.normalize_name(name),
      place_type: place_type,
      country_code: country_code,
      country_name: country_name,
      admin_area: admin_area,
      latitude: latitude,
      longitude: longitude,
      importance_score: importance_score.to_f,
      source: source,
      metadata: metadata || {}
    )
    place.save!

    sync_aliases!(place, [name, *Array(aliases)])
    1
  end

  def sync_aliases!(place, names)
    normalized_seen = Set.new
    names.compact.each do |name|
      normalized = Place.normalize_name(name)
      next if normalized.blank? || normalized_seen.include?(normalized)

      normalized_seen << normalized
      place.place_aliases.find_or_initialize_by(normalized_name: normalized).tap do |record|
        record.name = name.to_s
        record.alias_type = normalized == place.normalized_name ? "official" : "common"
        record.save!
      end
    end
  end

  def best_alias(aliases)
    aliases.find { |name| name.match?(/[^\x00-\x7F]/) } || aliases.first
  end

  def infer_place_type(name)
    normalized = name.to_s.downcase
    return "airport" if normalized.match?(/\b(airport|heathrow|gatwick|jfk|lax|o'hare|ohare|dulles|haneda|narita|schiphol|changi)\b/)
    return "region" if normalized.match?(/\b(sea|strait|gulf|bank|valley|camp|refugee|territories|crimea|donbas)\b/)

    "city"
  end

  def global_importance_score(aliases)
    base = aliases.size > 1 ? 0.58 : 0.5
    aliases.any? { |name| name.length > 12 } ? base + 0.03 : base
  end

  def profile_importance_score(priority)
    return 0.65 if priority <= 0

    (1.0 - [priority, 100].min / 200.0).round(3)
  end
end
