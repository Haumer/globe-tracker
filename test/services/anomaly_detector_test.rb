require "test_helper"

class AnomalyDetectorTest < ActiveSupport::TestCase
  test "detect finds emergency squawk flights" do
    Flight.create!(
      icao24: "anom-7500", callsign: "HIJACK1",
      latitude: 40.0, longitude: -74.0, altitude: 30000,
      origin_country: "US", military: false, squawk: "7500"
    )

    anomalies = AnomalyDetector.detect
    emergency = anomalies.select { |a| a[:type] == "emergency_flight" }

    assert_equal 1, emergency.size
    assert_equal 10, emergency.first[:severity]
    assert_includes emergency.first[:title], "Hijack"
  end

  test "detect finds significant earthquakes" do
    Earthquake.create!(
      external_id: "anom-eq-1", title: "Big One",
      magnitude: 7.0, latitude: 35.0, longitude: -118.0, depth: 10,
      event_time: 30.minutes.ago, fetched_at: Time.current
    )

    anomalies = AnomalyDetector.detect
    eq = anomalies.select { |a| a[:type] == "major_earthquake" }

    assert_equal 1, eq.size
    assert_includes eq.first[:title], "M7.0"
  end

  test "detect finds new jamming zones" do
    GpsJammingSnapshot.create!(
      cell_lat: 50.0, cell_lng: 35.0, total: 100, bad: 60,
      percentage: 60.0, level: "high", recorded_at: 30.minutes.ago
    )

    anomalies = AnomalyDetector.detect
    jamming = anomalies.select { |a| a[:type] == "new_jamming" }

    assert_equal 1, jamming.size
    assert_equal 8, jamming.first[:severity] # percentage > 50
  end

  test "detect returns empty with no data" do
    anomalies = AnomalyDetector.detect
    assert_empty anomalies
  end

  test "anomalies are sorted by severity descending" do
    Flight.create!(
      icao24: "anom-sort-7500", callsign: "HJ1",
      latitude: 40.0, longitude: -74.0, altitude: 30000,
      origin_country: "US", military: false, squawk: "7500"
    )
    Earthquake.create!(
      external_id: "anom-eq-sort", title: "M5.5 quake",
      magnitude: 5.5, latitude: 35.0, longitude: -118.0, depth: 10,
      event_time: 30.minutes.ago, fetched_at: Time.current
    )

    anomalies = AnomalyDetector.detect
    severities = anomalies.map { |a| a[:severity] }
    assert_equal severities, severities.sort.reverse
  end
end
