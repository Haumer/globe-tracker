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

    assert_difference("Railway.count", 1) do
      RailwayImportService.import!
    end

    railway = Railway.last
    assert_in_delta 16.369876, railway.coordinates.first.first, 0.000001
    assert_in_delta 48.210654, railway.coordinates.first.last, 0.000001
  ensure
    Net::HTTP.define_singleton_method(:get, original)
  end
end
