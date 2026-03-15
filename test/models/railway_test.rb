require "test_helper"

class RailwayTest < ActiveSupport::TestCase
  test "creation with basic fields" do
    railway = Railway.create!(
      category: 1,
      electrified: 1,
      continent: "Europe",
      min_lat: 46.0, max_lat: 49.0,
      min_lng: 9.0, max_lng: 17.0,
      coordinates: [[16.3, 48.2], [15.4, 47.0]]
    )
    assert railway.persisted?
    assert_equal "Europe", railway.continent
  end

  test "coordinates defaults to empty array" do
    railway = Railway.create!(category: 0, electrified: 0, continent: "Asia")
    assert_equal [], railway.coordinates
  end

  test "bounding box fields stored correctly" do
    railway = Railway.create!(
      continent: "Europe",
      min_lat: 46.0, max_lat: 49.0,
      min_lng: 9.0, max_lng: 17.0,
      coordinates: [[10.0, 47.0]]
    )
    assert_in_delta 46.0, railway.min_lat, 0.01
    assert_in_delta 49.0, railway.max_lat, 0.01
  end
end
