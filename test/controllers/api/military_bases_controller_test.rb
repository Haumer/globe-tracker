require "test_helper"

class Api::MilitaryBasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @base1 = MilitaryBase.create!(
      external_id: "mb-001",
      name: "Ramstein Air Base",
      base_type: "air_force",
      country: "Germany",
      operator: "USAF",
      latitude: 49.44,
      longitude: 7.60,
      fetched_at: Time.current,
    )
    @base2 = MilitaryBase.create!(
      external_id: "mb-002",
      name: "Norfolk Naval Station",
      base_type: "navy",
      country: "United States",
      operator: "USN",
      latitude: 36.95,
      longitude: -76.30,
      fetched_at: Time.current,
    )
  end

  test "GET /api/military_bases returns JSON array" do
    get "/api/military_bases"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert data.length >= 2
  end

  test "response rows contain expected positional fields" do
    get "/api/military_bases"
    data = JSON.parse(response.body)

    row = data.find { |r| r[0] == @base1.id }
    assert_not_nil row
    # [id, lat, lng, name, base_type, country, operator]
    assert_in_delta 49.44, row[1], 0.01
    assert_in_delta 7.60, row[2], 0.01
    assert_equal "Ramstein Air Base", row[3]
    assert_equal "air_force", row[4]
    assert_equal "Germany", row[5]
    assert_equal "USAF", row[6]
  end

  test "bbox filtering works" do
    get "/api/military_bases", params: { north: 50, south: 48, east: 8, west: 7 }
    data = JSON.parse(response.body)
    ids = data.map { |r| r[0] }
    assert_includes ids, @base1.id
    assert_not_includes ids, @base2.id
  end

  test "bbox filtering excludes bases outside bounds" do
    get "/api/military_bases", params: { north: 10, south: 5, east: 10, west: 5 }
    data = JSON.parse(response.body)
    assert_equal 0, data.length
  end

  test "excludes unnamed bunker/stellung/trench logistics bases" do
    MilitaryBase.create!(
      external_id: "mb-bunker",
      name: "Old Bunker Site",
      base_type: "logistics",
      latitude: 49.0, longitude: 7.0,
      fetched_at: Time.current,
    )

    get "/api/military_bases"
    data = JSON.parse(response.body)
    names = data.map { |r| r[3] }
    assert_not names.include?("Old Bunker Site")
  end

  test "includes named logistics bases without bunker in name" do
    MilitaryBase.create!(
      external_id: "mb-depot",
      name: "Supply Depot Alpha",
      base_type: "logistics",
      latitude: 49.0, longitude: 7.0,
      fetched_at: Time.current,
    )

    get "/api/military_bases"
    data = JSON.parse(response.body)
    names = data.map { |r| r[3] }
    assert_includes names, "Supply Depot Alpha"
  end

  test "limits results to 500" do
    get "/api/military_bases"
    data = JSON.parse(response.body)
    assert data.length <= 500
  end

  test "does not require authentication" do
    get "/api/military_bases"
    assert_response :success
  end
end
