require "test_helper"

class Api::FireClustersControllerTest < ActionDispatch::IntegrationTest
  setup do
    FireCluster.delete_all
    @extreme = create_cluster("fc_extreme", 47.9, -120.5, 5_000.0)
    @major = create_cluster("fc_major", 40.0, -100.0, 250.0)
    @minor = create_cluster("fc_minor", 10.0, 10.0, 4.0)
  end

  def create_cluster(external_id, lat, lng, mw)
    FireCluster.create!(
      external_id: external_id, latitude: lat, longitude: lng,
      intensity_mw: mw, latest_mw: mw, tier: FireCluster.tier_for(mw),
      pixel_count: 3, pass_count: 2, detection_count: 6,
      first_detected_at: 5.hours.ago, last_detected_at: 1.hour.ago,
      satellites: ["NOAA-20"], computed_at: Time.current
    )
  end

  test "GET /api/fire_clusters returns all clusters strongest first" do
    get "/api/fire_clusters"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 3, data.size
    assert_equal "fc_extreme", data.first[0]
    assert_equal [5000.0, 250.0, 4.0], data.map { |row| row[3] }
  end

  test "tier is carried in the payload so the client need not re-derive it" do
    get "/api/fire_clusters"

    tiers = JSON.parse(response.body).map { |row| row[4] }
    assert_equal ["extreme", "major", "minor"], tiers
  end

  test "limit caps the response at the strongest fires rather than an arbitrary slice" do
    get "/api/fire_clusters", params: { limit: 2 }

    data = JSON.parse(response.body)
    assert_equal ["fc_extreme", "fc_major"], data.map { |row| row[0] }
  end

  test "a limit above the runaway guard cannot raise it" do
    get "/api/fire_clusters", params: { limit: Api::FireClustersController::MAX_CLUSTERS + 5_000 }
    assert_response :success

    assert_equal 3, JSON.parse(response.body).size
  end

  test "a junk limit falls back to the runaway guard instead of returning nothing" do
    get "/api/fire_clusters", params: { limit: "0" }
    assert_response :success
    assert_equal 3, JSON.parse(response.body).size

    get "/api/fire_clusters", params: { limit: "-5" }
    assert_response :success
    assert_equal 3, JSON.parse(response.body).size
  end

  test "notable filter returns only the discretely-renderable fires" do
    get "/api/fire_clusters", params: { notable: 1 }

    data = JSON.parse(response.body)
    assert_equal 2, data.size
    refute_includes data.map { |row| row[0] }, "fc_minor"
  end

  test "tier filter narrows to one band" do
    get "/api/fire_clusters", params: { tier: "extreme" }

    data = JSON.parse(response.body)
    assert_equal 1, data.size
    assert_equal "fc_extreme", data.first[0]
  end

  test "bounds filter restricts to the viewport" do
    get "/api/fire_clusters", params: { lamin: 45, lamax: 50, lomin: -125, lomax: -115 }

    data = JSON.parse(response.body)
    assert_equal 1, data.size
    assert_equal "fc_extreme", data.first[0]
  end

  test "partial bounds are ignored rather than half-applied" do
    get "/api/fire_clusters", params: { lamin: 45, lamax: 50 }

    assert_response :success
    assert_equal 3, JSON.parse(response.body).size
  end

  test "GET /api/fire_clusters/:id returns the full observation series" do
    [["Suomi NPP", "VIIRS", 3.hours.ago, 1200.0, 40],
     ["NOAA-20", "VIIRS", 2.hours.ago, 4800.0, 130],
     ["NOAA-21", "VIIRS", 1.hour.ago, 4600.0, 155]].each_with_index do |(sat, inst, at, mw, px), i|
      FireObservation.create!(fire_cluster: @extreme, external_id: "#{@extreme.external_id}:#{i}:#{sat}",
                              satellite: sat, instrument: inst, acq_datetime: at,
                              frp_mw: mw, pixel_count: px, latitude: 47.9, longitude: -120.5)
    end

    get "/api/fire_clusters/#{@extreme.external_id}"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "fc_extreme", body["id"]
    assert_equal 3, body["observations"].size

    series = body["observations"]
    assert_equal [1200.0, 4800.0, 4600.0], series.map { |point| point["mw"] }, "must be chronological"
    assert_equal ["Suomi NPP", "NOAA-20", "NOAA-21"], series.map { |point| point["satellite"] }
    assert_equal [40, 130, 155], series.map { |point| point["pixels"] }
    assert_equal "growing", body["trend"]
  end

  test "unknown cluster id is a 404 rather than a 500" do
    get "/api/fire_clusters/fc_does_not_exist"
    assert_response :not_found
  end

  test "endpoint is public" do
    get "/api/fire_clusters"
    assert_response :success
  end
end
