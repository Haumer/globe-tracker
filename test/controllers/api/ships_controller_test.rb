require "test_helper"

class Api::ShipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ship = Ship.create!(
      mmsi: "211000001",
      name: "MV Test Vessel",
      ship_type: 70,
      latitude: 54.0,
      longitude: 10.0,
      speed: 12.5,
      heading: 180,
      course: 175,
      destination: "HAMBURG",
      flag: "DE",
      updated_at: Time.current,
    )
  end

  test "GET /api/ships returns JSON array" do
    with_env("AISSTREAM_API_KEY", nil) do
      get "/api/ships"
      assert_response :success

      data = JSON.parse(response.body)
      assert_kind_of Array, data
      assert_equal "ready", response.headers["X-Source-Status"]
      assert_equal "0", response.headers["X-Source-Configured"]
    end
  end

  test "ships response contains expected fields" do
    get "/api/ships", params: { lamin: 53.0, lamax: 55.0, lomin: 9.0, lomax: 11.0 }
    data = JSON.parse(response.body)
    ship = data.find { |s| s["mmsi"] == "211000001" }

    assert_not_nil ship
    assert_equal "MV Test Vessel", ship["name"]
    assert_in_delta 54.0, ship["latitude"], 0.01
  end

  test "stale ships are excluded" do
    Ship.create!(
      mmsi: "211000002",
      name: "Old Vessel",
      latitude: 54.0, longitude: 10.0,
      speed: 0, heading: 0,
      updated_at: 8.hours.ago,
    )

    get "/api/ships", params: { lamin: 53.0, lamax: 55.0, lomin: 9.0, lomax: 11.0 }
    data = JSON.parse(response.body)
    mmsis = data.map { |s| s["mmsi"] }
    assert_not_includes mmsis, "211000002"
  end

  test "empty ships response exposes unconfigured source status" do
    Ship.delete_all

    with_env("AISSTREAM_API_KEY", nil) do
      get "/api/ships"
      assert_response :success
      assert_equal "unconfigured", response.headers["X-Source-Status"]
      assert_equal "0", response.headers["X-Source-Configured"]
    end
  end

  private

  def with_env(key, value)
    original = ENV[key]

    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end

    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end
end
