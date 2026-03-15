require "test_helper"

class FireHotspotTest < ActiveSupport::TestCase
  setup do
    @fire = FireHotspot.create!(
      external_id: "FIRE-TEST-001",
      latitude: -33.8,
      longitude: 151.2,
      brightness: 330.5,
      confidence: "high",
      satellite: "Suomi NPP",
      frp: 45.2,
      acq_datetime: 1.hour.ago,
      fetched_at: Time.current,
    )
  end

  test "within_bounds filters by lat/lng" do
    results = FireHotspot.within_bounds(lamin: -35.0, lamax: -32.0, lomin: 150.0, lomax: 152.0)
    assert_includes results, @fire

    results = FireHotspot.within_bounds(lamin: 0.0, lamax: 5.0, lomin: 0.0, lomax: 5.0)
    assert_not_includes results, @fire
  end

  test "recent scope returns fires from last 48 hours" do
    old = FireHotspot.create!(
      external_id: "FIRE-TEST-002",
      latitude: -34.0, longitude: 150.0,
      acq_datetime: 3.days.ago,
      fetched_at: Time.current,
    )

    assert_includes FireHotspot.recent, @fire
    assert_not_includes FireHotspot.recent, old
  end

  test "SATELLITE_NORAD mapping has expected satellites" do
    assert_equal 37849, FireHotspot::SATELLITE_NORAD["Suomi NPP"]
    assert_equal 27424, FireHotspot::SATELLITE_NORAD["Aqua"]
    assert_nil FireHotspot::SATELLITE_NORAD["Unknown"]
  end

  test "unique external_id constraint" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      FireHotspot.create!(
        external_id: "FIRE-TEST-001",
        latitude: -34.0, longitude: 150.0,
        fetched_at: Time.current,
      )
    end
  end
end
