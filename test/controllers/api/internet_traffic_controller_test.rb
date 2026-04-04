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
