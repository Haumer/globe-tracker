require "test_helper"

class BackgroundRefreshApiTest < ActionDispatch::IntegrationTest
  test "earthquakes endpoint returns cached records" do
    Earthquake.create!(
      external_id: "eq-1",
      title: "Cached quake",
      magnitude: 4.2,
      magnitude_type: "ml",
      latitude: 48.2,
      longitude: 16.3,
      depth: 10.0,
      event_time: 1.hour.ago,
      fetched_at: 10.minutes.ago
    )

    get "/api/earthquakes"

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body.length
    assert_equal "eq-1", body.first["id"]
  end

  test "earthquakes timeline request with time params returns success" do
    get "/api/earthquakes", params: { from: 2.hours.ago.iso8601, to: Time.current.iso8601 }
    assert_response :success
  end

  test "internet traffic endpoint returns cached snapshot" do
    InternetTrafficSnapshot.create!(
      country_code: "AT",
      country_name: "Austria",
      traffic_pct: 10.5,
      attack_origin_pct: 2.2,
      attack_target_pct: 1.1,
      recorded_at: 2.hours.ago
    )
    File.write(
      CloudflareRadarService.attack_pairs_cache_path,
      [{ origin: "AT", target: "DE", origin_name: "Austria", target_name: "Germany", pct: 1.5 }].to_json
    )

    get "/api/internet_traffic"

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "AT", body["traffic"].first["code"]
    assert_equal "AT", body["attack_pairs"].first["origin"]
  ensure
    path = CloudflareRadarService.attack_pairs_cache_path
    File.delete(path) if File.exist?(path)
  end

  test "submarine cables endpoint returns cached data" do
    SubmarineCable.create!(
      cable_id: "cable-1",
      name: "Test Cable",
      color: "#00bcd4",
      coordinates: [[[16.3, 48.2], [2.3, 48.8]]],
      fetched_at: 8.days.ago
    )
    File.write(
      SubmarineCableRefreshService.landing_points_cache_path,
      [{ id: "lp-1", name: "Vienna", lat: 48.2, lng: 16.3 }].to_json
    )

    get "/api/submarine_cables"

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "cable-1", body["cables"].first["id"]
    assert_equal "lp-1", body["landingPoints"].first["id"]
  ensure
    path = SubmarineCableRefreshService.landing_points_cache_path
    File.delete(path) if File.exist?(path)
  end

  test "satellites endpoint returns cached category data" do
    Satellite.create!(
      name: "ISS (ZARYA)",
      tle_line1: "1 25544U 98067A   26071.50000000  .00016717  00000+0  10270-3 0  9995",
      tle_line2: "2 25544  51.6423  53.1234 0004104 130.5360 329.6013 15.50012345678901",
      category: "stations",
      norad_id: 25_544,
      updated_at: 7.hours.ago
    )

    get "/api/satellites", params: { category: "stations" }

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body.length
    assert_equal 25_544, body.first["norad_id"]
  end
end
