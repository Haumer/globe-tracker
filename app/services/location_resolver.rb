class LocationResolver
  include NewsGeocodable

  LOCATION_AMBIGUOUS_PUBLISHER_SUFFIXES = [
    "New York Times",
    "The New York Times",
    "Washington Post",
    "The Washington Post",
    "Los Angeles Times",
    "The Los Angeles Times",
    "Wall Street Journal",
    "The Wall Street Journal",
    "Times of Israel",
    "The Times of Israel",
  ].freeze
  PUBLISHER_SUFFIX_PATTERN = /
    (?:\s+(?:-|\||:)\s*|\s+)
    (?:#{LOCATION_AMBIGUOUS_PUBLISHER_SUFFIXES.sort_by { |suffix| -suffix.length }.map { |suffix| Regexp.escape(suffix) }.join("|")})
    \z
  /ix

  Result = Struct.new(
    :latitude,
    :longitude,
    :place_name,
    :country_code,
    :admin_area,
    :basis,
    :precision,
    :kind,
    :confidence,
    :metadata,
    keyword_init: true
  ) do
    def coordinates
      return nil if latitude.blank? || longitude.blank?

      [latitude, longitude]
    end

    def to_news_event_attributes
      {
        latitude: latitude,
        longitude: longitude,
        geocode_place_name: place_name,
        geocode_country_code: country_code,
        geocode_admin_area: admin_area,
        geocode_basis: basis,
        geocode_precision: precision || "unknown",
        geocode_kind: kind || "unknown",
        geocode_confidence: confidence.to_f,
        geocode_metadata: metadata || {},
      }
    end
  end

  SEEDED_CITY_COUNTRY_CANDIDATES = {
    ["london", "gb"] => { coords: [51.5074, -0.1278], place_name: "London", admin_area: "England" },
    ["london", "ca"] => { coords: [42.9849, -81.2453], place_name: "London", admin_area: "Ontario" },
    ["paris", "fr"] => { coords: [48.8566, 2.3522], place_name: "Paris", admin_area: "Ile-de-France" },
    ["paris", "us"] => { coords: [33.6609, -95.5555], place_name: "Paris", admin_area: "Texas" },
    ["tripoli", "ly"] => { coords: [32.8872, 13.1913], place_name: "Tripoli", admin_area: nil },
    ["tripoli", "lb"] => { coords: [34.4367, 35.8497], place_name: "Tripoli", admin_area: "North Governorate" },
  }.freeze

  class << self
    def resolve_event(**kwargs)
      new.resolve_event(**kwargs)
    end

    def news_event_attributes(result)
      result&.to_news_event_attributes || {}
    end
  end

  def resolve_event(title:, summary: nil, country_hint: nil, url: nil, city: nil, country: nil,
                    provided_latitude: nil, provided_longitude: nil, provided_place_name: nil,
                    provided_basis: nil)
    title_for_matching = title_without_publisher_suffix(title)

    candidates = [
      ai_city_candidate(city: city, country: country),
      title_city_candidate(title: title_for_matching, country_hint: country_hint),
      provided_coordinate_candidate(
        latitude: provided_latitude,
        longitude: provided_longitude,
        place_name: provided_place_name,
        basis: provided_basis
      ),
      title_country_candidate(title: [title_for_matching, summary].compact.join(" ")),
      country_hint_candidate(country_hint),
      domain_candidate(url),
    ].compact

    candidates.max_by { |candidate| [candidate.confidence.to_f, candidate_priority(candidate)] }
  end

  private

  def ai_city_candidate(city:, country:)
    city_name = normalized_place_text(city)
    country_code = normalize_country_code(country)
    return country_event_candidate(country_code, basis: "ai_country", confidence: 0.64) if city_name.blank? && country_code.present?
    return nil if city_name.blank?

    place = place_candidate(
      name: city_name,
      country_code: country_code,
      basis: country_code.present? ? "ai_place_country" : "ai_place",
      confidence: country_code.present? ? 0.93 : 0.83,
      metadata: { "input_city" => city, "input_country" => country }.compact
    )
    return place if place

    seeded = SEEDED_CITY_COUNTRY_CANDIDATES[[city_name, country_code]] if country_code.present?
    if seeded
      lat, lng = seeded.fetch(:coords)
      return result(
        lat: lat,
        lng: lng,
        place_name: seeded.fetch(:place_name),
        country_code: country_code,
        admin_area: seeded[:admin_area],
        basis: "ai_city_country_seeded",
        precision: "city",
        kind: "event",
        confidence: 0.92,
        metadata: { "input_city" => city, "input_country" => country }
      )
    end

    coords = CITY_COORDS[city_name]
    return nil unless coords

    result(
      lat: coords[0],
      lng: coords[1],
      place_name: city.to_s.squish.presence || city_name.titleize,
      country_code: country_code,
      basis: country_code.present? ? "ai_city_country" : "ai_city",
      precision: "city",
      kind: "event",
      confidence: country_code.present? ? 0.9 : 0.82,
      metadata: { "input_city" => city, "input_country" => country }.compact
    )
  end

  def title_city_candidate(title:, country_hint:)
    city_name = city_name_from_title(title) || gazetteer_name_from_title(title)
    return nil unless city_name

    country_code = normalize_country_code(country_hint)
    place = place_candidate(
      name: city_name,
      country_code: country_code,
      basis: country_code.present? ? "title_place_country" : "title_place",
      confidence: country_code.present? ? 0.91 : 0.85,
      metadata: { "matched_text" => city_name, "country_hint" => country_hint }.compact
    )
    return place if place

    seeded = SEEDED_CITY_COUNTRY_CANDIDATES[[city_name, country_code]] if country_code.present?
    if seeded
      lat, lng = seeded.fetch(:coords)
      return result(
        lat: lat,
        lng: lng,
        place_name: seeded.fetch(:place_name),
        country_code: country_code,
        admin_area: seeded[:admin_area],
        basis: "title_city_country_seeded",
        precision: "city",
        kind: "event",
        confidence: 0.9,
        metadata: { "matched_text" => city_name, "country_hint" => country_hint }.compact
      )
    end

    coords = CITY_COORDS[city_name]
    result(
      lat: coords[0],
      lng: coords[1],
      place_name: city_name.titleize,
      country_code: country_code,
      basis: country_code.present? ? "title_city_with_country_hint" : "title_city",
      precision: "city",
      kind: "event",
      confidence: country_code.present? ? 0.87 : 0.84,
      metadata: { "matched_text" => city_name, "country_hint" => country_hint }.compact
    )
  end

  def provided_coordinate_candidate(latitude:, longitude:, place_name:, basis:)
    return nil if latitude.blank? || longitude.blank?

    lat = latitude.to_f
    lng = longitude.to_f
    return nil if lat.zero? && lng.zero?

    result(
      lat: lat,
      lng: lng,
      place_name: place_name,
      basis: basis.presence || "provided_coordinates",
      precision: place_name.present? ? "place" : "unknown",
      kind: "event",
      confidence: provided_coordinate_confidence(basis),
      metadata: { "provided_place_name" => place_name }.compact
    )
  end

  def title_country_candidate(title:)
    return nil if title.blank?

    lower = title.downcase
    TITLE_GEO_PATTERNS.each do |pattern|
      next unless lower.include?(pattern)

      code = normalize_country_code(TITLE_GEO_MAP[pattern])
      return country_event_candidate(code, basis: "title_country_keyword", confidence: 0.58, matched_text: pattern) if code
    end
    nil
  end

  def country_hint_candidate(country_hint)
    code = normalize_country_code(country_hint)
    return nil unless code

    coords = COUNTRY_COORDS[code]
    return nil unless coords

    result(
      lat: coords[0],
      lng: coords[1],
      place_name: country_hint.to_s.squish.presence,
      country_code: code,
      basis: "source_country_hint",
      precision: "country",
      kind: "source_context",
      confidence: 0.34,
      metadata: { "country_hint" => country_hint }
    )
  end

  def domain_candidate(url)
    coords = geocode_from_domain(url)
    return nil unless coords

    result(
      lat: coords[0],
      lng: coords[1],
      basis: "publisher_domain",
      precision: "country",
      kind: "source_context",
      confidence: 0.24,
      metadata: { "url" => url }
    )
  end

  def country_event_candidate(code, basis:, confidence:, matched_text: nil)
    return nil unless code

    coords = COUNTRY_COORDS[code]
    return nil unless coords

    result(
      lat: coords[0],
      lng: coords[1],
      country_code: code,
      basis: basis,
      precision: "country",
      kind: "event",
      confidence: confidence,
      metadata: { "matched_text" => matched_text }.compact
    )
  end

  def place_candidate(name:, basis:, confidence:, metadata:, country_code: nil)
    return nil unless places_available?

    place = Place.lookup(name, country_code: country_code).first
    return nil unless place

    result(
      lat: place.latitude,
      lng: place.longitude,
      place_name: place.name,
      country_code: place.country_code,
      admin_area: place.admin_area,
      basis: basis,
      precision: place_precision(place),
      kind: "event",
      confidence: place_confidence(place, base: confidence),
      metadata: metadata.merge(
        "place_id" => place.id,
        "place_source" => place.source,
        "place_canonical_key" => place.canonical_key
      )
    )
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    nil
  end

  def places_available?
    defined?(Place) && ActiveRecord::Base.connection.data_source_exists?("places")
  end

  def place_precision(place)
    place.place_type == "city" ? "city" : place.place_type
  end

  def place_confidence(place, base:)
    adjustment = place.country_code.present? ? 0.02 : 0.0
    [base.to_f + adjustment, 0.99].min.round(2)
  end

  def city_name_from_title(title)
    return nil if title.blank?

    CITY_PATTERNS.find { |city| CITY_REGEXES[city].match?(title) }
  end

  def gazetteer_name_from_title(title)
    return nil if title.blank? || !places_available?

    normalized_title = Place.normalize_name(title)
    PlaceAlias
      .select(:normalized_name)
      .order(Arel.sql("length(normalized_name) DESC"))
      .find { |place_alias| normalized_title.match?(/(?:\A|\s)#{Regexp.escape(place_alias.normalized_name)}(?:\s|\z)/) }
      &.normalized_name
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    nil
  end

  def normalize_country_code(value)
    normalized = value.to_s.downcase.squish
    return nil if normalized.blank? || normalized == "unspecified"

    code = COUNTRY_NAME_MAP[normalized] || normalized
    code = "gb" if code == "uk"
    return code if COUNTRY_COORDS.key?(code)

    nil
  end

  def normalized_place_text(value)
    normalized = value.to_s.downcase.squish
    return nil if normalized.blank? || normalized == "unspecified"

    normalized
  end

  def title_without_publisher_suffix(title)
    title.to_s.squish.sub(PUBLISHER_SUFFIX_PATTERN, "").squish
  end

  def result(lat:, lng:, basis:, precision:, kind:, confidence:, place_name: nil, country_code: nil, admin_area: nil, metadata: {})
    Result.new(
      latitude: lat,
      longitude: lng,
      place_name: place_name,
      country_code: country_code,
      admin_area: admin_area,
      basis: basis,
      precision: precision,
      kind: kind,
      confidence: confidence.to_f.round(2),
      metadata: metadata || {}
    )
  end

  def provided_coordinate_confidence(basis)
    case basis.to_s
    when "gdelt_geojson" then 0.72
    when "manual", "verified" then 0.95
    else 0.66
    end
  end

  def candidate_priority(candidate)
    case candidate.basis
    when "ai_city_country_seeded", "ai_city_country" then 6
    when "title_city_country_seeded", "title_city_with_country_hint" then 5
    when "title_city", "ai_city" then 4
    when "gdelt_geojson", "provided_coordinates" then 3
    when "title_country_keyword", "ai_country" then 2
    else 1
    end
  end
end
