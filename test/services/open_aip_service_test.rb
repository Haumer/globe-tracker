require "test_helper"

class OpenAipServiceTest < ActiveSupport::TestCase
  test "TYPE_LABELS maps type codes to names" do
    assert_equal "Restricted Area", OpenAipService::TYPE_LABELS[1]
    assert_equal "Danger", OpenAipService::TYPE_LABELS[2]
    assert_equal "Prohibited", OpenAipService::TYPE_LABELS[3]
    assert_equal "Military", OpenAipService::TYPE_LABELS[14]
    assert_equal "Warning", OpenAipService::TYPE_LABELS[18]
  end

  test "centroid computes center of polygon" do
    geometry = {
      "type" => "Polygon",
      "coordinates" => [[[10.0, 47.0], [11.0, 47.0], [11.0, 48.0], [10.0, 48.0], [10.0, 47.0]]]
    }
    lat, lng = OpenAipService.send(:centroid, geometry)
    assert_in_delta 47.4, lat, 0.2
    assert_in_delta 10.4, lng, 0.2
  end

  test "centroid handles Point geometry" do
    geometry = { "type" => "Point", "coordinates" => [10.0, 47.0] }
    lat, lng = OpenAipService.send(:centroid, geometry)
    assert_in_delta 47.0, lat, 0.01
    assert_in_delta 10.0, lng, 0.01
  end

  test "estimate_radius returns default for missing coordinates" do
    assert_equal 5556, OpenAipService.send(:estimate_radius, { "type" => "Polygon" })
  end

  test "estimate_radius computes radius for polygon" do
    geometry = {
      "type" => "Polygon",
      "coordinates" => [[[10.0, 47.0], [10.1, 47.0], [10.1, 47.1], [10.0, 47.1], [10.0, 47.0]]]
    }
    radius = OpenAipService.send(:estimate_radius, geometry)
    assert radius > 1000
  end

  test "convert_altitude handles different units" do
    assert_equal 3281, OpenAipService.send(:convert_altitude, { "value" => 1000, "unit" => 0 })
    assert_equal 5000, OpenAipService.send(:convert_altitude, { "value" => 5000, "unit" => 1 })
    assert_equal 10_000, OpenAipService.send(:convert_altitude, { "value" => 100, "unit" => 6 })
    assert_nil OpenAipService.send(:convert_altitude, nil)
  end
end
