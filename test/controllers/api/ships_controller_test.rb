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

  test "civilian filter excludes naval vessels" do
    Ship.create!(
      mmsi: "211000003",
      name: "USS Example",
      ship_type: 35,
      latitude: 54.1,
      longitude: 10.1,
      speed: 14.0,
      heading: 90,
      updated_at: Time.current,
    )

    get "/api/ships", params: { filter: "civilian", lamin: 53.0, lamax: 55.0, lomin: 9.0, lomax: 11.0 }
    data = JSON.parse(response.body)
    mmsis = data.map { |s| s["mmsi"] }

    assert_includes mmsis, "211000001"
    assert_not_includes mmsis, "211000003"
  end

  test "naval filter includes ships by type and callsign pattern" do
    Ship.create!(
      mmsi: "211000004",
      name: "USS Example",
      ship_type: 70,
      latitude: 54.2,
      longitude: 10.2,
      speed: 12.0,
      heading: 45,
      updated_at: Time.current,
    )
    Ship.create!(
      mmsi: "211000005",
      name: "Coast Patrol",
      ship_type: 55,
      latitude: 54.3,
      longitude: 10.3,
      speed: 10.0,
      heading: 135,
      updated_at: Time.current,
    )

    get "/api/ships", params: { filter: "naval", lamin: 53.0, lamax: 55.0, lomin: 9.0, lomax: 11.0 }
    data = JSON.parse(response.body)
    mmsis = data.map { |s| s["mmsi"] }

    assert_includes mmsis, "211000004"
    assert_includes mmsis, "211000005"
    assert_not_includes mmsis, "211000001"
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
