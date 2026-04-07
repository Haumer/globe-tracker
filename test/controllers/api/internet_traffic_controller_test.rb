require "test_helper"

class Api::InternetTrafficControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/internet_traffic returns json with traffic data" do
    InternetTrafficSnapshot.create!(
      country_code: "US",
      country_name: "United States",
      traffic_pct: 25.0,
      attack_origin_pct: 10.0,
      attack_target_pct: 5.0,
      recorded_at: Time.current
    )

    with_cloudflare_source(api_token: nil, cached_attack_pairs: []) do
      get "/api/internet_traffic"
      assert_response :success

      data = JSON.parse(response.body)
      assert_kind_of Array, data["traffic"]
      assert data["traffic"].any? { |t| t["code"] == "US" }
      assert_equal "ready", response.headers["X-Source-Status"]
      assert_equal "0", response.headers["X-Source-Configured"]
    end
  end

  test "GET /api/internet_traffic with empty DB returns empty traffic" do
    with_cloudflare_source(api_token: nil, cached_attack_pairs: []) do
      get "/api/internet_traffic"
      assert_response :success

      data = JSON.parse(response.body)
      assert_equal [], data["traffic"]
      assert_equal "unconfigured", response.headers["X-Source-Status"]
      assert_equal "0", response.headers["X-Source-Configured"]
    end
  end

  test "GET /api/internet_traffic at timestamp returns historical batch without live attack pairs" do
    old_time = 3.hours.ago
    new_time = 30.minutes.ago

    InternetTrafficSnapshot.create!(
      country_code: "US",
      country_name: "United States",
      traffic_pct: 81.0,
      attack_origin_pct: 4.0,
      attack_target_pct: 2.0,
      recorded_at: old_time
    )
    InternetTrafficSnapshot.create!(
      country_code: "US",
      country_name: "United States",
      traffic_pct: 95.0,
      attack_origin_pct: 8.0,
      attack_target_pct: 5.0,
      recorded_at: new_time
    )
    InternetAttackPairSnapshot.create!(
      origin_country_code: "US",
      target_country_code: "DE",
      origin_country_name: "United States",
      target_country_name: "Germany",
      attack_pct: 14.2,
      recorded_at: old_time
    )
    InternetAttackPairSnapshot.create!(
      origin_country_code: "US",
      target_country_code: "FR",
      origin_country_name: "United States",
      target_country_name: "France",
      attack_pct: 7.7,
      recorded_at: new_time
    )

    with_cloudflare_source(api_token: "token", cached_attack_pairs: [{ origin: "US", target: "DE", pct: 14.2 }]) do
      get "/api/internet_traffic", params: { at: 2.hours.ago.iso8601 }
      assert_response :success

      data = JSON.parse(response.body)
      us = data["traffic"].find { |row| row["code"] == "US" }

      assert_not_nil us
      assert_in_delta 81.0, us["traffic"], 0.01
      assert_equal "DE", data["attack_pairs"].first["target"]
      assert_equal true, data["playback"]
    end
  end

  private

  def with_cloudflare_source(api_token:, cached_attack_pairs:)
    singleton = CloudflareRadarService.singleton_class
    original_api_token = singleton.instance_method(:api_token)
    original_cached_attack_pairs = singleton.instance_method(:cached_attack_pairs)

    singleton.define_method(:api_token) { api_token }
    singleton.define_method(:cached_attack_pairs) { cached_attack_pairs }

    yield
  ensure
    singleton.define_method(:api_token, original_api_token)
    singleton.define_method(:cached_attack_pairs, original_cached_attack_pairs)
  end
end
