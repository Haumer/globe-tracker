require "test_helper"

class WeatherAlertTest < ActiveSupport::TestCase
  setup do
    @alert = WeatherAlert.create!(
      external_id: "urn:oid:2.49.0.1.840.0.test001",
      event: "Severe Thunderstorm Warning",
      severity: "Severe",
      urgency: "Immediate",
      headline: "Severe Thunderstorm Warning for Test County",
      latitude: 35.0,
      longitude: -90.0,
      onset: 1.hour.ago,
      expires: 2.hours.from_now,
      fetched_at: Time.current,
    )
  end

  test "within_bounds filters by lat/lng" do
    results = WeatherAlert.within_bounds(lamin: 34.0, lamax: 36.0, lomin: -91.0, lomax: -89.0)
    assert_includes results, @alert

    results = WeatherAlert.within_bounds(lamin: 40.0, lamax: 42.0, lomin: -75.0, lomax: -73.0)
    assert_not_includes results, @alert
  end

  test "active scope includes non-expired alerts" do
    assert_includes WeatherAlert.active, @alert
  end

  test "active scope excludes expired alerts" do
    expired = WeatherAlert.create!(
      external_id: "urn:oid:2.49.0.1.840.0.test002",
      event: "Flood Warning",
      severity: "Moderate",
      latitude: 36.0, longitude: -91.0,
      onset: 5.hours.ago,
      expires: 1.hour.ago,
      fetched_at: Time.current,
    )

    assert_not_includes WeatherAlert.active, expired
  end

  test "active scope includes alerts with nil expires" do
    no_expiry = WeatherAlert.create!(
      external_id: "urn:oid:2.49.0.1.840.0.test003",
      event: "Wind Advisory",
      severity: "Minor",
      latitude: 37.0, longitude: -92.0,
      onset: 1.hour.ago,
      expires: nil,
      fetched_at: Time.current,
    )

    assert_includes WeatherAlert.active, no_expiry
  end

  test "recent scope returns alerts from last 48 hours" do
    old = WeatherAlert.create!(
      external_id: "urn:oid:2.49.0.1.840.0.test004",
      event: "Heat Advisory",
      severity: "Moderate",
      latitude: 38.0, longitude: -93.0,
      onset: 3.days.ago,
      fetched_at: Time.current,
    )

    assert_includes WeatherAlert.recent, @alert
    assert_not_includes WeatherAlert.recent, old
  end
end
