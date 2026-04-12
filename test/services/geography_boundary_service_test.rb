require "test_helper"

class GeographyBoundaryServiceTest < ActiveSupport::TestCase
  test "filters and compacts boundary payloads by country code" do
    payload = {
      "type" => "FeatureCollection",
      "features" => [
        feature("Germany", "DEU", "DE", "DE-BY", "Bayern", 48.7, 11.5, "drop-me"),
        feature("Austria", "AUT", "AT", "AT-9", "Vienna", 48.2, 16.4, "drop-me"),
        feature("France", "FRA", "FR", "FR-IDF", "Ile-de-France", 48.8, 2.4, "drop-me"),
      ],
    }

    filtered = GeographyBoundaryService.send(:filtered_payload, payload, country_codes: "DE,AT")

    assert_equal "FeatureCollection", filtered["type"]
    assert_equal 2, filtered["features"].size
    assert_equal %w[Bayern Vienna], filtered["features"].map { |item| item.dig("properties", "name") }
    assert_equal %w[DEU AUT], filtered["features"].map { |item| item.dig("properties", "adm0_a3") }
    assert_nil filtered["features"].first.dig("properties", "unused")
  end

  test "returns original boundary payload when no country filter is provided" do
    payload = {
      "type" => "FeatureCollection",
      "features" => [feature("Germany", "DEU", "DE", "DE-BY", "Bayern", 48.7, 11.5, "kept")],
    }

    assert_same payload, GeographyBoundaryService.send(:filtered_payload, payload, country_codes: nil)
  end

  test "caches filtered boundary variants" do
    cache = ActiveSupport::Cache::MemoryStore.new
    payload = {
      "type" => "FeatureCollection",
      "features" => [feature("Germany", "DEU", "DE", "DE-BY", "Bayern", 48.7, 11.5, "drop-me")],
    }

    Rails.stub(:cache, cache) do
      first = GeographyBoundaryService.send(
        :filtered_payload,
        payload,
        country_codes: "DE",
        cache_key: "test-boundaries",
        cache_ttl: 1.hour
      )

      payload["features"] = []
      second = GeographyBoundaryService.send(
        :filtered_payload,
        payload,
        country_codes: "DE",
        cache_key: "test-boundaries",
        cache_ttl: 1.hour
      )

      assert_equal first, second
      assert_equal 1, second["features"].size
    end
  end

  test "returns cached filtered boundary before loading global payload" do
    cache = ActiveSupport::Cache::MemoryStore.new
    cached = {
      "type" => "FeatureCollection",
      "features" => [feature("Germany", "DEU", "DE", "DE-BY", "Bayern", 48.7, 11.5, "cached")],
    }
    cache.write("geography-boundaries:admin1:v1:filtered:DE:v1", cached)

    Rails.stub(:cache, cache) do
      GeographyBoundaryService.stub(:http_get, ->(*) { raise "should not load global payload" }) do
        assert_equal cached, GeographyBoundaryService.fetch("admin1", country_codes: "DE")
      end
    end
  end

  private

  def feature(country, alpha3, alpha2, iso_3166_2, name, lat, lng, unused)
    {
      "type" => "Feature",
      "geometry" => { "type" => "Polygon", "coordinates" => [[[10.0, 45.0], [11.0, 45.0], [11.0, 46.0], [10.0, 45.0]]] },
      "properties" => {
        "admin" => country,
        "adm0_a3" => alpha3,
        "iso_a2" => alpha2,
        "iso_3166_2" => iso_3166_2,
        "name" => name,
        "name_en" => name,
        "woe_name" => name,
        "gn_name" => name,
        "latitude" => lat,
        "longitude" => lng,
        "unused" => unused,
      },
    }
  end
end
