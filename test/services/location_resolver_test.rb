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

  test "lowercase common words are not treated as place names" do
    resolver = LocationResolver.new
    # "base", "college" and "pala" are all real GeoNames settlements.
    assert_nil resolver.send(:gazetteer_name_from_title, "drones seen over a military base today")
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
