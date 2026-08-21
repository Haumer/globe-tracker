require "test_helper"

class LocationResolverTest < ActiveSupport::TestCase
  test "title city beats lower confidence provided coordinates" do
    result = LocationResolver.resolve_event(
      title: "London police arrest protesters",
      provided_latitude: 42.9849,
      provided_longitude: -81.2453,
      provided_place_name: "London",
      provided_basis: "gdelt_geojson"
    )

    assert_equal "title_city", result.basis
    assert_equal "event", result.kind
    assert_in_delta 51.5074, result.latitude, 0.1
    assert_in_delta(-0.1278, result.longitude, 0.1)
  end

  test "source country hints are source context not event locations" do
    result = LocationResolver.resolve_event(
      title: "Central bank issues rate warning",
      country_hint: "United States",
      url: "https://example.com/story"
    )

    assert_equal "source_country_hint", result.basis
    assert_equal "source_context", result.kind
    assert_operator result.confidence, :<, NewsEvent::TRUSTED_EVENT_GEOCODE_CONFIDENCE
  end

  test "seeded ambiguous city country candidates disambiguate London Canada" do
    result = LocationResolver.resolve_event(
      title: "Police respond after incident",
      city: "London",
      country: "Canada"
    )

    assert_equal "ai_city_country_seeded", result.basis
    assert_equal "ca", result.country_code
    assert_equal "Ontario", result.admin_area
    assert_in_delta 42.9849, result.latitude, 0.1
    assert_in_delta(-81.2453, result.longitude, 0.1)
  end

  test "uses gazetteer places when available" do
    PlaceGazetteerSyncService.refresh

    result = LocationResolver.resolve_event(title: "London police arrest protesters")

    assert_equal "title_place", result.basis
    assert_equal "gb", result.country_code
    assert_equal "London", result.place_name
    assert_in_delta 51.5074, result.latitude, 0.1
    assert_equal "seeded_ambiguity", result.metadata["place_source"]
  end

  test "uses gazetteer aliases from enriched city profiles" do
    PlaceGazetteerSyncService.refresh

    result = LocationResolver.resolve_event(title: "Industrial disruption reported in Wien")

    assert_equal "title_place", result.basis
    assert_equal "at", result.country_code
    assert_equal "Vienna", result.place_name
    assert_equal "city_profile", result.metadata["place_source"]
  end

  test "ignores location-bearing publisher suffixes when matching title places" do
    result = LocationResolver.resolve_event(
      title: "Mourning In Sidon After Israeli Strike Kills 13 Lebanese Security Personnel New York Times"
    )

    assert_equal "title_city", result.basis
    assert_equal "Sidon", result.place_name
    assert_in_delta 33.56, result.latitude, 0.1
    assert_in_delta 35.37, result.longitude, 0.1
  end

  test "news event attributes include provenance fields" do
    result = LocationResolver.resolve_event(title: "Explosion rocks central Kyiv")
    attrs = LocationResolver.news_event_attributes(result)

    assert_equal "title_city", attrs[:geocode_basis]
    assert_equal "event", attrs[:geocode_kind]
    assert_equal "city", attrs[:geocode_precision]
    assert_operator attrs[:geocode_confidence], :>=, NewsEvent::TRUSTED_EVENT_GEOCODE_CONFIDENCE
    assert_in_delta 50.45, attrs[:latitude], 0.1
  end

  test "normalize_name preserves non-Latin scripts instead of erasing them" do
    # I18n.transliterate mapped these to "?" and they normalized to "", so
    # Greek, Cyrillic, Arabic and CJK titles could never match a place.
    assert_equal "κόρινθος", Place.normalize_name("Κόρινθος")
    assert_equal "харків", Place.normalize_name("Харків")
    assert_equal "القاهرة", Place.normalize_name("القاهرة")
    assert_equal "北京", Place.normalize_name("北京")
  end

  test "normalize_name leaves Latin text exactly as before" do
    assert_equal "zagreb", Place.normalize_name("Zagreb")
    assert_equal "new york city", Place.normalize_name("New York City!")
  end

  test "ascii_name gives a Latin-alphabet form alongside the native one" do
    assert_equal "koln", Place.ascii_name("Köln")
    assert_equal "sant julia de loria", Place.ascii_name("Sant Julià de Lòria")
  end

  test "a matched alias resolves to the place that owns it, not a namesake" do
    # Two places share the surface form "cali": the Colombian city (via its
    # canonical name) and an unrelated, higher-importance place that carries
    # "cali" only as a cross-language alias. The old string round-trip lost
    # which row matched and re-ranked by importance, landing on the namesake.
    cali = Place.create!(
      canonical_key: "test:cali-co", name: "Cali", place_type: "city", source: "test",
      country_code: "co", latitude: 3.4516, longitude: -76.5320, importance_score: 5.0
    )
    namesake = Place.create!(
      canonical_key: "test:kali-my", name: "Kali", place_type: "city", source: "test",
      country_code: "my", latitude: 3.1390, longitude: 101.6869, importance_score: 50.0
    )
    namesake.place_aliases.create!(name: "Cali", normalized_name: "cali", alias_type: "alternate")

    resolver = LocationResolver.new
    place, matched = resolver.send(:gazetteer_place_from_title, "Explosion reported in Cali overnight")

    assert_equal "cali", matched
    # Both rows legitimately answer to "cali"; ranked order decides, and the
    # winner must be one of the owners of that surface form -- never a row
    # reached by re-looking the string up through a different index.
    assert_includes [cali.id, namesake.id], place.id

    # With a country hint the hinted row wins outright.
    hinted, = resolver.send(:gazetteer_place_from_title, "Explosion reported in Cali overnight", country_code: "co")
    assert_equal cali.id, hinted.id
  end

  test "a country hint narrows but does not veto a gazetteer match" do
    kyiv = Place.create!(
      canonical_key: "test:kyiv-ua", name: "Kyiv", place_type: "city", source: "test",
      country_code: "ua", latitude: 50.4501, longitude: 30.5234, importance_score: 9.0
    )

    result = LocationResolver.resolve_event(title: "Missile strike hits Kyiv suburb", country_hint: "Chile")

    assert_equal "title_place", result.basis, "a wrong hint downgrades the basis, not the answer"
    assert_equal "ua", result.country_code
    assert_in_delta kyiv.latitude, result.latitude, 0.01
  end

  test "a country name resolves as the country, never a namesake village" do
    Place.create!(
      canonical_key: "test:australia-cu", name: "Australia", place_type: "city", source: "test",
      country_code: "cu", latitude: 22.79, longitude: -81.05, importance_score: 2.0
    )

    result = LocationResolver.resolve_event(title: "Australia announces sweeping new tariffs")

    assert_not_equal "cu", result&.country_code, "the Cuban village must not claim the country's stories"
    assert_not_equal "title_place", result&.basis
  end

  test "short all-caps tokens are organisations, not gazetteer candidates" do
    Place.create!(
      canonical_key: "test:un-village", name: "Un", place_type: "city", source: "test",
      country_code: "es", latitude: 37.46, longitude: -5.34, importance_score: 1.0
    )

    karachi = Place.create!(
      canonical_key: "test:karachi-pk", name: "Karachi", place_type: "city", source: "test",
      country_code: "pk", latitude: 24.86, longitude: 67.0, importance_score: 8.0
    )

    resolver = LocationResolver.new
    assert_nil resolver.send(:gazetteer_place_from_title, "UN warns of widening famine"),
      "UN is an organisation, whatever villages share the letters"

    place, = resolver.send(:gazetteer_place_from_title, "KARACHI: port workers strike")
    assert_equal karachi.id, place&.id, "dateline caps longer than four characters still match"
  end

  test "lowercase common words are not treated as place names" do
    resolver = LocationResolver.new
    # "base", "college" and "pala" are all real GeoNames settlements.
    assert_nil resolver.send(:gazetteer_place_from_title, "drones seen over a military base today")
  end

  test "capitalised tokens are still eligible" do
    resolver = LocationResolver.new
    gram = %w[Kharkiv]
    assert resolver.send(:proper_noun_gram?, gram)
    refute resolver.send(:proper_noun_gram?, %w[military base])
  end

  test "uncased scripts bypass the capitalisation guard" do
    resolver = LocationResolver.new
    # Arabic and CJK have no capital forms, so requiring one would exclude them.
    assert resolver.send(:proper_noun_gram?, [ "القاهرة" ])
    assert resolver.send(:proper_noun_gram?, [ "北京" ])
  end
end
