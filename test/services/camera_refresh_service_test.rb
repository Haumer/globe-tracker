require "test_helper"

class CameraRefreshServiceTest < ActiveSupport::TestCase
  test "bbox_overlaps_nyc? returns true for NYC area" do
    service = CameraRefreshService.new(north: 40.8, south: 40.6, east: -73.9, west: -74.1)
    assert service.send(:bbox_overlaps_nyc?)
  end

  test "bbox_overlaps_nyc? returns false for non-NYC area" do
    service = CameraRefreshService.new(north: 48.3, south: 48.1, east: 16.5, west: 16.3)
    assert_not service.send(:bbox_overlaps_nyc?)
  end

  test "cell_keys generates grid cell cache keys" do
    service = CameraRefreshService.new(north: 41.0, south: 40.0, east: -73.0, west: -74.0)
    keys = service.send(:cell_keys)
    assert_kind_of Array, keys
    assert keys.any? { |k| k.start_with?("camera_cell:") }
  end

  test "normalize_windy extracts webcam data" do
    service = CameraRefreshService.new(north: 41.0, south: 40.0, east: -73.0, west: -74.0)
    windy_data = {
      "webcamId" => "12345",
      "title" => "NYC Skyline",
      "location" => { "latitude" => 40.7, "longitude" => -74.0, "city" => "New York", "region" => "NY", "country" => "US" },
      "player" => { "live" => { "embed" => "https://example.com/live" } },
      "images" => { "current" => { "preview" => "https://example.com/img.jpg", "icon" => "https://example.com/icon.jpg" } },
      "viewCount" => 1000,
      "lastUpdatedOn" => "2025-06-15",
    }

    result = service.send(:normalize_windy, windy_data)
    assert_equal "12345", result[:webcam_id]
    assert_equal "windy", result[:source]
    assert_equal "NYC Skyline", result[:title]
    assert_in_delta 40.7, result[:latitude], 0.01
    assert_equal true, result[:is_live]
  end

  test "CELL_TTL is defined" do
    assert_equal 10.minutes, CameraRefreshService::CELL_TTL
  end
end
