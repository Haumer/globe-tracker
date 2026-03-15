require "test_helper"

class NewsGeocodableTest < ActiveSupport::TestCase
  class GeoTester
    include NewsGeocodable
    public :resolve_location, :geocode_city_from_title, :geocode_from_title,
           :geocode_country, :geocode_country_name, :geocode_from_domain
  end

  setup do
    @tester = GeoTester.new
  end

  test "geocode_city_from_title finds known cities" do
    lat, lng = @tester.geocode_city_from_title("Explosion rocks central Kyiv")
    assert_in_delta 50.45, lat, 0.01
    assert_in_delta 30.52, lng, 0.01
  end

  test "geocode_city_from_title returns nil for unrecognized text" do
    assert_nil @tester.geocode_city_from_title("Unknown place has event")
  end

  test "geocode_city_from_title returns nil for blank" do
    assert_nil @tester.geocode_city_from_title(nil)
    assert_nil @tester.geocode_city_from_title("")
  end

  test "geocode_country looks up by code" do
    lat, lng = @tester.geocode_country("US")
    assert_in_delta 38.9, lat, 0.1
    assert_in_delta(-77.0, lng, 0.1)
  end

  test "geocode_country returns nil for blank" do
    assert_nil @tester.geocode_country(nil)
  end

  test "geocode_country_name resolves full country names" do
    lat, lng = @tester.geocode_country_name("Germany")
    assert_in_delta 52.5, lat, 0.1
    assert_in_delta 13.4, lng, 0.1
  end

  test "geocode_from_title resolves keywords like Kremlin" do
    lat, lng = @tester.geocode_from_title("Kremlin issues new warning")
    assert_in_delta 55.8, lat, 0.1
    assert_in_delta 37.6, lng, 0.1
  end

  test "geocode_from_domain resolves ccTLD" do
    lat, lng = @tester.geocode_from_domain("https://www.example.at/news")
    assert_in_delta 48.2, lat, 0.1
    assert_in_delta 16.4, lng, 0.1
  end

  test "geocode_from_domain resolves known publishers" do
    lat, lng = @tester.geocode_from_domain("https://www.jpost.com/article")
    assert_in_delta 31.8, lat, 0.1
  end

  test "geocode_from_domain returns nil for generic TLDs" do
    assert_nil @tester.geocode_from_domain("https://example.com/news")
  end

  test "resolve_location returns lat lng array" do
    result = @tester.resolve_location("us", "Earthquake hits San Francisco", nil)
    assert_instance_of Array, result
    assert_equal 2, result.size
  end
end
