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

  test "news event attributes include provenance fields" do
    result = LocationResolver.resolve_event(title: "Explosion rocks central Kyiv")
    attrs = LocationResolver.news_event_attributes(result)

    assert_equal "title_city", attrs[:geocode_basis]
    assert_equal "event", attrs[:geocode_kind]
    assert_equal "city", attrs[:geocode_precision]
    assert_operator attrs[:geocode_confidence], :>=, NewsEvent::TRUSTED_EVENT_GEOCODE_CONFIDENCE
    assert_in_delta 50.45, attrs[:latitude], 0.1
  end
end
