require "test_helper"

class NotamRefreshServiceTest < ActiveSupport::TestCase
  setup do
    @service = NotamRefreshService.new
    @now = Time.current
  end

  test "parse_faa_notam extracts Point geometry" do
    item = {
      "geometry" => { "type" => "Point", "coordinates" => [-77.0, 38.9] },
      "properties" => {
        "id" => "NOTAM-001",
        "text" => "TFR 3 NM RADIUS SFC TO FL180",
        "effectiveStart" => "2025-06-15T00:00:00Z",
        "effectiveEnd" => "2025-06-16T00:00:00Z",
      }
    }

    result = @service.send(:parse_faa_notam, item, @now)
    assert_not_nil result
    assert_equal "faa-NOTAM-001", result[:external_id]
    assert_in_delta 38.9, result[:latitude], 0.01
    assert_in_delta(-77.0, result[:longitude], 0.01)
    assert_equal 3.0, result[:radius_nm]
    assert_equal (3.0 * 1852).round, result[:radius_m]
  end

  test "parse_faa_notam extracts Polygon centroid" do
    item = {
      "geometry" => {
        "type" => "Polygon",
        "coordinates" => [[[-77.0, 38.0], [-77.0, 39.0], [-76.0, 39.0], [-76.0, 38.0], [-77.0, 38.0]]]
      },
      "properties" => {
        "id" => "NOTAM-002",
        "text" => "TFR FIRE ACTIVITY",
      }
    }

    result = @service.send(:parse_faa_notam, item, @now)
    assert_not_nil result
    assert_equal "Wildfire", result[:reason]
  end

  test "parse_faa_notam classifies VIP TFR" do
    item = {
      "geometry" => { "type" => "Point", "coordinates" => [-77.0, 38.9] },
      "properties" => {
        "id" => "NOTAM-003",
        "text" => "TFR VIP MOVEMENT POTUS",
      }
    }

    result = @service.send(:parse_faa_notam, item, @now)
    assert_equal "VIP Movement", result[:reason]
  end

  test "parse_faa_notam classifies Space Operations" do
    item = {
      "geometry" => { "type" => "Point", "coordinates" => [-80.6, 28.6] },
      "properties" => {
        "id" => "NOTAM-004",
        "text" => "TFR SPACE LAUNCH OPERATIONS",
      }
    }

    result = @service.send(:parse_faa_notam, item, @now)
    assert_equal "Space Operations", result[:reason]
  end

  test "parse_faa_notam returns nil without coordinates" do
    item = {
      "properties" => { "id" => "NOTAM-005", "text" => "Some NOTAM" }
    }

    result = @service.send(:parse_faa_notam, item, @now)
    assert_nil result
  end

  test "parse_faa_notam returns nil without id" do
    item = {
      "geometry" => { "type" => "Point", "coordinates" => [-77.0, 38.9] },
      "properties" => { "text" => "Some NOTAM" }
    }

    result = @service.send(:parse_faa_notam, item, @now)
    assert_nil result
  end

  test "parse_faa_notam parses altitude from text" do
    item = {
      "geometry" => { "type" => "Point", "coordinates" => [-77.0, 38.9] },
      "properties" => {
        "id" => "NOTAM-006",
        "text" => "TFR SFC TO FL180",
      }
    }

    result = @service.send(:parse_faa_notam, item, @now)
    assert_equal 0, result[:alt_low_ft]
    assert_equal 18000, result[:alt_high_ft]
  end
end
