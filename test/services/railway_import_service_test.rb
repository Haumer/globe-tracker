require "test_helper"

class RailwayImportServiceTest < ActiveSupport::TestCase
  test "SOURCE_URL points to natural earth railroads geojson" do
    assert RailwayImportService::SOURCE_URL.include?("natural-earth-vector")
    assert RailwayImportService::SOURCE_URL.end_with?(".geojson")
  end

  test "import! is a class method" do
    assert RailwayImportService.respond_to?(:import!)
  end
end
