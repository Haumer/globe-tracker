require "test_helper"

class NotamTest < ActiveSupport::TestCase
  setup do
    @notam = Notam.create!(
      external_id: "NOTAM-TEST-001",
      source: "FAA",
      latitude: 48.0,
      longitude: 11.0,
      radius_nm: 5,
      radius_m: 9260,
      reason: "Military",
      text: "Restricted airspace for military exercise",
      country: "DE",
      effective_start: 1.hour.ago,
      effective_end: 2.hours.from_now,
      fetched_at: Time.current,
    )
  end

  test "within_bounds filters by lat/lng" do
    results = Notam.within_bounds(lamin: 47.0, lamax: 49.0, lomin: 10.0, lomax: 12.0)
    assert_includes results, @notam

    results = Notam.within_bounds(lamin: 50.0, lamax: 52.0, lomin: 10.0, lomax: 12.0)
    assert_not_includes results, @notam
  end

  test "active scope includes non-expired notams" do
    assert_includes Notam.active, @notam
  end

  test "active scope excludes expired notams" do
    expired = Notam.create!(
      external_id: "NOTAM-TEST-002",
      latitude: 49.0, longitude: 12.0,
      effective_start: 5.hours.ago,
      effective_end: 1.hour.ago,
      fetched_at: Time.current,
    )

    assert_not_includes Notam.active, expired
  end

  test "active scope includes notams with nil effective_end" do
    permanent = Notam.create!(
      external_id: "NOTAM-TEST-003",
      latitude: 50.0, longitude: 13.0,
      effective_start: 1.day.ago,
      effective_end: nil,
      fetched_at: Time.current,
    )

    assert_includes Notam.active, permanent
  end

  test "recent scope returns notams from last 48 hours" do
    old = Notam.create!(
      external_id: "NOTAM-TEST-004",
      latitude: 51.0, longitude: 14.0,
      effective_start: 3.days.ago,
      fetched_at: Time.current,
    )

    assert_includes Notam.recent, @notam
    assert_not_includes Notam.recent, old
  end
end
