require "test_helper"

class NewsEventGeocodeBackfillServiceTest < ActiveSupport::TestCase
  test "backfills trusted title locations over bad legacy coordinates" do
    event = NewsEvent.create!(
      url: "https://example.com/london-protest",
      title: "London police arrest protesters",
      name: "Legacy source",
      latitude: 43.0,
      longitude: -81.0,
      category: "unrest",
      published_at: 1.hour.ago,
      fetched_at: Time.current
    )

    count = NewsEventGeocodeBackfillService.backfill_recent(limit: 10)

    assert_equal 1, count
    event.reload
    assert_equal "event", event.geocode_kind
    assert_operator event.geocode_confidence, :>=, NewsEvent::TRUSTED_EVENT_GEOCODE_CONFIDENCE
    assert_in_delta 51.51, event.latitude, 0.1
    assert_in_delta(-0.13, event.longitude, 0.1)
  end

  test "marks unresolved legacy coordinates as unverified" do
    event = NewsEvent.create!(
      url: "https://example.com/unclear",
      title: "Unclear security update",
      name: "Legacy source",
      latitude: 43.0,
      longitude: -81.0,
      category: "conflict",
      published_at: 1.hour.ago,
      fetched_at: Time.current
    )

    count = NewsEventGeocodeBackfillService.backfill_recent(limit: 10)

    assert_equal 1, count
    event.reload
    assert_equal "legacy_unverified", event.geocode_kind
    assert_equal "legacy_coordinates", event.geocode_basis
    assert_operator event.geocode_confidence, :<, NewsEvent::TRUSTED_EVENT_GEOCODE_CONFIDENCE
    assert_in_delta 43.0, event.latitude, 0.1
  end

  test "does not replace legacy coordinates with publisher domain context" do
    event = NewsEvent.create!(
      url: "https://independent.co.uk/unclear",
      title: "Unclear security update",
      name: "Legacy source",
      latitude: 43.0,
      longitude: -81.0,
      category: "conflict",
      published_at: 1.hour.ago,
      fetched_at: Time.current
    )

    count = NewsEventGeocodeBackfillService.backfill_recent(limit: 10)

    assert_equal 1, count
    event.reload
    assert_equal "legacy_unverified", event.geocode_kind
    assert_equal "legacy_coordinates", event.geocode_basis
    assert_in_delta 43.0, event.latitude, 0.1
    assert_in_delta(-81.0, event.longitude, 0.1)
  end
end
