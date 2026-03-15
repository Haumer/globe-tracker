require "test_helper"

class EarthquakeRefreshServiceTest < ActiveSupport::TestCase
  test "parse_records with valid USGS GeoJSON data" do
    service = EarthquakeRefreshService.new
    data = {
      "features" => [
        {
          "id" => "us7000test",
          "properties" => {
            "place" => "10km NE of Ridgecrest, CA",
            "mag" => 5.5,
            "magType" => "mww",
            "time" => 1710000000000,
            "url" => "https://earthquake.usgs.gov/earthquakes/eventpage/us7000test",
            "tsunami" => 0,
            "alert" => "green",
          },
          "geometry" => {
            "coordinates" => [-117.5, 35.7, 8.0]
          }
        }
      ]
    }

    records = service.send(:parse_records, data)

    assert_equal 1, records.size
    record = records.first
    assert_equal "us7000test", record[:external_id]
    assert_equal "10km NE of Ridgecrest, CA", record[:title]
    assert_in_delta 5.5, record[:magnitude], 0.01
    assert_in_delta 35.7, record[:latitude], 0.01
    assert_in_delta(-117.5, record[:longitude], 0.01)
    assert_in_delta 8.0, record[:depth], 0.01
    assert_equal false, record[:tsunami]
    assert_equal "green", record[:alert]
  end

  test "parse_records skips features without coordinates" do
    service = EarthquakeRefreshService.new
    data = {
      "features" => [
        {
          "id" => "no-coords",
          "properties" => { "place" => "Unknown", "mag" => 3.0 },
          "geometry" => { "coordinates" => nil }
        }
      ]
    }

    records = service.send(:parse_records, data)
    assert_empty records
  end

  test "parse_records handles empty features array" do
    service = EarthquakeRefreshService.new
    data = { "features" => [] }

    records = service.send(:parse_records, data)
    assert_empty records
  end

  test "upsert_records persists earthquake data" do
    service = EarthquakeRefreshService.new
    now = Time.current
    records = [
      {
        external_id: "eq-upsert-1",
        title: "Upsert Test",
        magnitude: 4.5,
        magnitude_type: "ml",
        latitude: 48.0,
        longitude: 16.0,
        depth: 10.0,
        event_time: 1.hour.ago,
        url: "https://example.com",
        tsunami: false,
        alert: nil,
        fetched_at: now,
        created_at: now,
        updated_at: now,
      }
    ]

    service.send(:upsert_records, records)
    eq = Earthquake.find_by(external_id: "eq-upsert-1")
    assert_not_nil eq
    assert_equal "Upsert Test", eq.title
    assert_in_delta 4.5, eq.magnitude, 0.01
  end

  test "parse_records handles tsunami flag correctly" do
    service = EarthquakeRefreshService.new
    data = {
      "features" => [
        {
          "id" => "tsunami-test",
          "properties" => { "place" => "Pacific", "mag" => 8.0, "time" => 1710000000000, "tsunami" => 1 },
          "geometry" => { "coordinates" => [-170.0, -15.0, 30.0] }
        }
      ]
    }

    records = service.send(:parse_records, data)
    assert_equal true, records.first[:tsunami]
  end
end
