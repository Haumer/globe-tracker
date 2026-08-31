class LocationResolver
  include NewsGeocodable

  LOCATION_AMBIGUOUS_PUBLISHER_SUFFIX_MATCHES = {
    "New York Times" => "new york",
    "The New York Times" => "new york",
    "Washington Post" => "washington",
    "The Washington Post" => "washington",
    "Los Angeles Times" => "los angeles",
    "The Los Angeles Times" => "los angeles",
    "Wall Street Journal" => "new york",
    "The Wall Street Journal" => "new york",
    "Times of Israel" => "israel",
    "The Times of Israel" => "israel",
  }.freeze
  LOCATION_AMBIGUOUS_PUBLISHER_SUFFIXES = LOCATION_AMBIGUOUS_PUBLISHER_SUFFIX_MATCHES.keys.freeze
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
                    provided_basis: nil, publisher: nil)
    title_for_matching = title_without_publisher_suffix(title, publisher)

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
    country_code = normalize_country_code(country_hint)
    city_name = city_name_from_title(title)

    if city_name.nil?
      # The gazetteer path resolves to a Place row, never back through a bare
      # string. The hint narrows the choice but does not veto it: a Chilean
      # feed's country hint must not stop "Kyiv" resolving to Ukraine.
      place, matched_text = gazetteer_place_from_title(title, country_code: country_code)
      return nil unless place

      hint_matched = country_code.present? && place.country_code == country_code
      return place_result(
        place,
        basis: hint_matched ? "title_place_country" : "title_place",
        confidence: hint_matched ? 0.91 : 0.85,
        metadata: { "matched_text" => matched_text, "country_hint" => country_hint }.compact
      )
    end

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

    # The hint narrows, it does not veto: a Chilean feed's country hint must
    # not stop "Kyiv" resolving to Ukraine. Retry without the hint before
    # falling back, at the unhinted basis and confidence.
    if country_code.present?
      place = place_candidate(
        name: city_name,
        basis: "title_place",
        confidence: 0.85,
        metadata: { "matched_text" => city_name, "country_hint" => country_hint }.compact
      )
      return place if place
    end

    # Every gazetteer alias used to originate from CITY_COORDS, so this lookup
    # could not miss. Since the gazetteer is loaded from GeoNames that no
    # longer holds: a matched name may have no CITY_COORDS entry. Reaching
    # here means neither the hinted nor the unhinted gazetteer knew the name,
    # so the hint's country is an unverified guess -- claim only the city.
    coords = CITY_COORDS[city_name]
    return nil if coords.nil?

    result(
      lat: coords[0],
      lng: coords[1],
      place_name: city_name.titleize,
      basis: "title_city",
      precision: "city",
      kind: "event",
      confidence: 0.84,
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

    # "Colombia" as a name means the country unless the caller explicitly
    # points at a different country's namesake village (country_code "cu").
    mapped = COUNTRY_NAME_MAP[Place.normalize_name(name)]
    return nil if mapped && (country_code.blank? || country_code == mapped)

    place = Place.lookup(name, country_code: country_code).first
    return nil unless place

    place_result(place, basis: basis, confidence: confidence, metadata: metadata)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    nil
  end

  def place_result(place, basis:, confidence:, metadata:)
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

  # Longest place name we will look for, in words ("san jose del monte").
  MAX_PLACE_NGRAM = 4

  # Asks "are any of this title's word-sequences a known place?" rather than
  # "does this title contain any known place?".
  #
  # The latter reads every alias into Ruby and regex-tests them one by one, so
  # its cost grows with the size of the gazetteer: ~5ms per article at 630
  # aliases, which extrapolates to seconds per article once a real gazetteer
  # is loaded. This form issues indexed lookups whose cost depends on the
  # length of the title instead, so the gazetteer can grow freely.
  #
  # Returns [place, matched_text], and the Place is the row whose name or
  # alias actually matched. The previous form returned only the matched
  # string and re-looked it up, which let an alias of one place resolve to a
  # completely different place carrying the same surface form -- "Cali"
  # matched via Colombia's city and resolved to a Malaysian toponym.
  #
  # Longest match still wins, so "new york" beats a bare "york"; among
  # equal-length matches the ranked scope prefers country-coded rows and
  # higher importance, so a title naming several same-named places resolves
  # to the most prominent one every run.
  def gazetteer_place_from_title(title, country_code: nil)
    return nil if title.blank? || !places_available?

    # N-grams are built from the original casing, not the normalized string,
    # because capitalisation is the only thing separating a place from an
    # ordinary word: "military base in Germany" must not match the French
    # commune La Bassée via "base", and "College sports bill" must not match
    # College, Alaska. Uncased scripts (Arabic, Hebrew, CJK) are exempt.
    tokens = title.to_s.split(/\s+/)
    return nil if tokens.empty?

    candidates = (1..MAX_PLACE_NGRAM).flat_map do |n|
      tokens.each_cons(n).filter_map do |gram|
        next unless proper_noun_gram?(gram)
        next if n == 1 && acronym_token?(gram.first)

        normalized = Place.normalize_name(gram.join(" "))
        next if normalized.blank?
        # A country name in a headline is the country, not its namesake
        # village -- "Australia" must not resolve to Australia, Cuba. The
        # country-keyword candidate downstream claims these at country
        # precision instead.
        next if COUNTRY_NAME_MAP.key?(normalized)

        normalized
      end
    end.uniq
    return nil if candidates.empty?

    matches = PlaceAlias.where(normalized_name: candidates).pluck(:normalized_name, :place_id) +
      Place.where(normalized_name: candidates).pluck(:normalized_name, :id)
    return nil if matches.empty?

    best_length = matches.map { |name, _| name.length }.max
    best = matches.select { |name, _| name.length == best_length }
    ids = best.map(&:last).uniq

    scope = Place.where(id: ids)
    place = (scope.where(country_code: country_code).ranked.first if country_code.present?)
    place ||= scope.ranked.first
    return nil unless place

    [place, best.find { |_, id| id == place.id }&.first]
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    nil
  end

  # A short all-caps token is an organisation or a country code before it is
  # a place: "UN", "EU", "NATO", "GOP". Real places written in caps are
  # dateline style ("KARACHI:") and comfortably longer than four characters
  # more often than not, so the guard costs little and stops org initialisms
  # matching whichever village happens to share the letters.
  def acronym_token?(token)
    word = token.gsub(/\A[^[[:alnum:]]]+|[^[[:alnum:]]]+\z/, "")
    word.length.between?(1, 4) && word == word.upcase && word != word.downcase
  end

  # True when every token could be part of a proper noun. A character whose
  # upcase and downcase are identical belongs to an uncased script, where
  # capitalisation carries no signal, so those pass through untouched.
  def proper_noun_gram?(gram)
    gram.all? do |token|
      word = token.gsub(/\A[^[[:alnum:]]]+|[^[[:alnum:]]]+\z/, "")
      next false if word.blank?

      first = word[0]
      first.downcase == first.upcase || first == first.upcase
    end
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

  # LOCATION_AMBIGUOUS_PUBLISHER_SUFFIXES names ten mastheads by hand, and every
  # publisher missing from it geocoded its own articles to the place in its
  # name. On a live board "Jerusalem" was a 48-member situation, 74% of it
  # Jerusalem Post, matched at confidence 0.82 -- and it held "Ukraine war
  # transforms European security architecture" and "US military chiefs warn
  # Hegseth". Bangalore was 83% Deccan Herald, Karachi 100% DAWN. The list does
  # not need to be guessed at: Google News names the publisher on every item and
  # a single-site feed is its own publisher, so the caller passes the name it
  # already has and the suffix comes off before anything matches a gazetteer.
  def title_without_publisher_suffix(title, publisher = nil)
    stripped = title.to_s.squish.sub(PUBLISHER_SUFFIX_PATTERN, "").squish
    return stripped if publisher.blank?

    # A title that is nothing but its publisher keeps its text: there is no
    # story left to match either way, and an empty string is harder to debug.
    stripped.sub(publisher_suffix_pattern(publisher), "").squish.presence || stripped
  end

  def publisher_suffix_pattern(publisher)
    /(?:\s+(?:-|\||:|–|—)\s*|\s+)#{Regexp.escape(publisher.to_s.squish)}\z/i
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
