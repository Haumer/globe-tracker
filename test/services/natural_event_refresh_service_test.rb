require "test_helper"

class NaturalEventRefreshServiceTest < ActiveSupport::TestCase
  setup do
    @service = NaturalEventRefreshService.new
  end

  test "parse_records with valid EONET data" do
    data = {
      "events" => [
        {
          "id" => "EONET_1234",
          "title" => "Wildfire - California",
          "categories" => [{ "id" => "wildfires", "title" => "Wildfires" }],
          "geometry" => [
            { "date" => "2025-06-15T00:00:00Z", "coordinates" => [-120.5, 37.8], "magnitudeValue" => nil }
          ],
          "link" => "https://eonet.gsfc.nasa.gov/api/v3/events/EONET_1234",
          "sources" => [{ "id" => "InciWeb", "url" => "https://inciweb.example.com" }],
        }
      ]
    }

    records = @service.send(:parse_records, data)
    assert_equal 1, records.size

    record = records.first
    assert_equal "EONET_1234", record[:external_id]
    assert_equal "Wildfire - California", record[:title]
    assert_equal "wildfires", record[:category_id]
    assert_in_delta 37.8, record[:latitude], 0.01
    assert_in_delta(-120.5, record[:longitude], 0.01)
  end

  test "parse_records skips events without geometry" do
    data = {
      "events" => [
        { "id" => "EONET_9999", "title" => "No Geometry Event", "geometry" => nil, "categories" => [] }
      ]
    }

    records = @service.send(:parse_records, data)
    assert_equal 0, records.size
  end

  test "parse_records handles empty events array" do
    data = { "events" => [] }
    records = @service.send(:parse_records, data)
    assert_equal 0, records.size
  end

  test "parse_records handles missing events key" do
    data = {}
    records = @service.send(:parse_records, data)
    assert_equal 0, records.size
  end
end
