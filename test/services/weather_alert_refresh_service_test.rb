require "test_helper"

class WeatherAlertRefreshServiceTest < ActiveSupport::TestCase
  setup do
    @service = WeatherAlertRefreshService.new
  end

  test "extract_centroid from Point geometry" do
    geo = { "type" => "Point", "coordinates" => [-95.5, 30.2] }
    lat, lng = @service.send(:extract_centroid, geo)
    assert_in_delta 30.2, lat, 0.01
    assert_in_delta(-95.5, lng, 0.01)
  end

  test "extract_centroid from Polygon geometry" do
    geo = {
      "type" => "Polygon",
      "coordinates" => [
        [[-100.0, 30.0], [-100.0, 32.0], [-98.0, 32.0], [-98.0, 30.0], [-100.0, 30.0]]
      ]
    }
    lat, lng = @service.send(:extract_centroid, geo)
    assert_in_delta 31.2, lat, 0.5
    assert_in_delta(-99.2, lng, 0.5)
  end

  test "extract_centroid from MultiPolygon geometry" do
    geo = {
      "type" => "MultiPolygon",
      "coordinates" => [
        [[[-100.0, 30.0], [-100.0, 32.0], [-98.0, 30.0]]],
        [[[-90.0, 35.0], [-90.0, 36.0], [-89.0, 35.0]]]
      ]
    }
    lat, lng = @service.send(:extract_centroid, geo)
    assert_kind_of Float, lat
    assert_kind_of Float, lng
  end

  test "extract_centroid returns nil pair for nil geometry" do
    lat, lng = @service.send(:extract_centroid, nil)
    assert_nil lat
    assert_nil lng
  end

  test "extract_centroid returns nil pair for unknown geometry type" do
    geo = { "type" => "LineString", "coordinates" => [[-100, 30], [-99, 31]] }
    lat, lng = @service.send(:extract_centroid, geo)
    assert_nil lat
    assert_nil lng
  end

  test "approximate_from_area finds state centroid" do
    lat, lng = @service.send(:approximate_from_area, "Parts of TX and OK")
    assert_not_nil lat
    assert_not_nil lng
  end

  test "approximate_from_area returns nil for unknown area" do
    lat, lng = @service.send(:approximate_from_area, "Unknown Region XYZ")
    assert_nil lat
    assert_nil lng
  end

  test "parse_records with valid NWS data" do
    data = {
      "features" => [
        {
          "properties" => {
            "id" => "alert-001",
            "event" => "Tornado Warning",
            "severity" => "Extreme",
            "urgency" => "Immediate",
            "certainty" => "Observed",
            "headline" => "Tornado Warning for Dallas County",
            "description" => "A tornado was observed...",
            "areaDesc" => "Dallas County, TX",
            "senderName" => "NWS Fort Worth",
            "onset" => "2025-06-15T18:00:00Z",
            "expires" => "2025-06-15T19:00:00Z",
          },
          "geometry" => {
            "type" => "Point",
            "coordinates" => [-96.8, 32.8]
          }
        }
      ]
    }

    records = @service.send(:parse_records, data)
    assert_equal 1, records.size
    assert_equal "alert-001", records.first[:external_id]
    assert_equal "Tornado Warning", records.first[:event]
  end

  test "parse_records handles empty features" do
    data = { "features" => [] }
    records = @service.send(:parse_records, data)
    assert_equal 0, records.size
  end
end
