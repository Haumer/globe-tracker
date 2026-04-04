require "test_helper"

class RailwayImportServiceTest < ActiveSupport::TestCase
  test "SOURCE_URL points to natural earth railroads geojson" do
    assert RailwayImportService::SOURCE_URL.include?("natural-earth-vector")
    assert RailwayImportService::SOURCE_URL.end_with?(".geojson")
  end

  test "import! is a class method" do
    assert RailwayImportService.respond_to?(:import!)
  end

  test "import! preserves source coordinate precision" do
    old_railway = Railway.create!(
      category: 1,
      electrified: 1,
      continent: "Europe",
      min_lat: 48.2,
      max_lat: 48.2,
      min_lng: 16.3,
      max_lng: 16.4,
      coordinates: [[16.3, 48.2], [16.4, 48.2]]
    )

    observation = TrainObservation.create!(
      external_id: "oebb-ice-101",
      source: "hafas",
      matched_railway: old_railway,
      snapped_latitude: 48.2,
      snapped_longitude: 16.35,
      snap_distance_m: 4.2,
      snap_confidence: "high",
      raw_payload: {},
      fetched_at: Time.current
    )

    payload = {
      "features" => [
        {
          "geometry" => {
            "coordinates" => [[16.369876, 48.210654], [16.401234, 48.219876]]
          },
          "properties" => {
            "category" => 1,
            "electric" => 1,
            "continent" => "Europe"
          }
        }
      ]
    }

    original = Net::HTTP.method(:get)
    Net::HTTP.define_singleton_method(:get) { |_uri| payload.to_json }

    assert_no_difference("Railway.count") do
      RailwayImportService.import!
    end

    railway = Railway.last
    assert_in_delta 16.369876, railway.coordinates.first.first, 0.000001
    assert_in_delta 48.210654, railway.coordinates.first.last, 0.000001
    observation.reload
    assert_nil observation.matched_railway_id
    assert_nil observation.snapped_latitude
    assert_nil observation.snap_confidence
  ensure
    Net::HTTP.define_singleton_method(:get, original)
  end
end
