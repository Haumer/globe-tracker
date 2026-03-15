require "test_helper"

class ConnectionFinderTest < ActiveSupport::TestCase
  test "find returns verified and nearby arrays" do
    result = ConnectionFinder.find(entity_type: "flight", lat: 48.2, lng: 16.3, metadata: {})
    assert result.key?(:verified)
    assert result.key?(:nearby)
    assert_kind_of Array, result[:verified]
    assert_kind_of Array, result[:nearby]
  end

  test "flight with emergency squawk returns verified emergency" do
    result = ConnectionFinder.find(
      entity_type: "flight",
      lat: 48.2, lng: 16.3,
      metadata: { squawk: "7700" },
    )

    emergency = result[:verified].find { |v| v[:type] == "emergency" }
    assert_not_nil emergency
    assert_equal "Emergency squawk 7700", emergency[:title]
    assert_equal "General emergency", emergency[:detail]
  end

  test "flight with hijack squawk" do
    result = ConnectionFinder.find(
      entity_type: "flight",
      lat: 48.2, lng: 16.3,
      metadata: { squawk: "7500" },
    )

    emergency = result[:verified].find { |v| v[:type] == "emergency" }
    assert_not_nil emergency
    assert_equal "Hijack", emergency[:detail]
  end

  test "earthquake finds nearby power plants" do
    PowerPlant.create!(
      gppd_idnr: "CONN-PP-001",
      name: "Nearby Nuclear",
      latitude: 35.5, longitude: -118.5,
      capacity_mw: 1000, primary_fuel: "Nuclear",
    )

    result = ConnectionFinder.find(entity_type: "earthquake", lat: 35.0, lng: -118.0, metadata: {})
    plant_conn = result[:verified].find { |v| v[:type] == "power_plant" }

    assert_not_nil plant_conn
    assert plant_conn[:title].include?("power plant")
  end

  test "fire_hotspot connects detecting satellite" do
    Satellite.create!(
      name: "Suomi NPP", norad_id: 37849,
      tle_line1: "1 37849U", tle_line2: "2 37849",
      category: "weather",
    )

    result = ConnectionFinder.find(
      entity_type: "fire_hotspot",
      lat: -33.8, lng: 151.2,
      metadata: { satellite: "Suomi NPP" },
    )

    sat_conn = result[:verified].find { |v| v[:type] == "satellite" }
    assert_not_nil sat_conn
    assert_equal "Detected by Suomi NPP", sat_conn[:title]
  end

  test "unknown entity type returns empty results" do
    result = ConnectionFinder.find(entity_type: "unknown_thing", lat: 0, lng: 0, metadata: {})
    assert_kind_of Array, result[:verified]
    assert_kind_of Array, result[:nearby]
  end
end
