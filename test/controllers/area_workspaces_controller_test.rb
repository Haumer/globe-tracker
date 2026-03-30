require "test_helper"

class AreaWorkspacesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  SnapshotStub = Struct.new(:payload, :status) do
    def fresh?
      true
    end
  end

  setup do
    @user = User.create!(email: "areas@example.com", password: "password123")
    sign_in @user
  end

  def empty_snapshot_for(service)
    payload =
      if service == InsightSnapshotService
        InsightSnapshotService.empty_payload
      elsif service == ConflictPulseSnapshotService
        ConflictPulseSnapshotService.empty_payload
      else
        ChokepointSnapshotService.empty_payload
      end

    SnapshotStub.new(payload, "ready")
  end

  def with_stubbed_fetch(klass, snapshot)
    original = klass.method(:fetch_or_enqueue)
    klass.singleton_class.send(:define_method, :fetch_or_enqueue) { snapshot }
    yield
  ensure
    klass.singleton_class.send(:define_method, :fetch_or_enqueue, original)
  end

  def with_empty_area_snapshots
    with_stubbed_fetch(InsightSnapshotService, empty_snapshot_for(InsightSnapshotService)) do
      with_stubbed_fetch(ConflictPulseSnapshotService, empty_snapshot_for(ConflictPulseSnapshotService)) do
        with_stubbed_fetch(ChokepointSnapshotService, empty_snapshot_for(ChokepointSnapshotService)) do
          yield
        end
      end
    end
  end

  test "POST /areas creates an area workspace" do
    assert_difference("AreaWorkspace.count", 1) do
      post areas_path, as: :json, params: {
        area_workspace: {
          name: "Gulf States",
          scope_type: "preset_region",
          profile: "maritime",
          bounds: { lamin: 21.0, lamax: 32.0, lomin: 44.0, lomax: 57.0 },
          default_layers: ["ships", "chokepoints", "news"],
          scope_metadata: {
            region_key: "gulf-states",
            region_name: "Gulf States",
            description: "US/Iran tensions, oil infrastructure, military buildup, naval activity",
          },
        },
      }
    end

    assert_response :created

    data = JSON.parse(response.body)
    assert_equal "Gulf States", data["name"]
    assert_equal area_path(AreaWorkspace.order(:id).last), data["path"]
  end

  test "POST /areas redirects to the area page for html form submissions" do
    assert_difference("AreaWorkspace.count", 1) do
      post areas_path, params: {
        area_workspace: {
          name: "Hormuz Monitor",
          scope_type: "preset_region",
          profile: "maritime",
          bounds: { lamin: 23.0, lamax: 28.0, lomin: 54.0, lomax: 60.0 },
          default_layers: ["ships", "chokepoints", "news"],
          scope_metadata: {
            region_key: "strait-of-hormuz",
            region_name: "Strait of Hormuz",
            description: "Tracked from the globe region bar",
            camera: { lat: 26.2, lng: 56.5, height: 500_000, heading: 0, pitch: -0.8 },
          },
        },
      }
    end

    assert_redirected_to area_path(AreaWorkspace.order(:id).last)
  end

  test "GET /areas/:id renders an area summary" do
    area = @user.area_workspaces.create!(
      name: "Gulf monitor",
      scope_type: "country_set",
      profile: "general",
      bounds: { lamin: 24.0, lamax: 26.5, lomin: 54.0, lomax: 56.5 },
      scope_metadata: { countries: ["United Arab Emirates"] },
      default_layers: ["news", "insights", "flights"]
    )

    NewsEvent.create!(
      url: "https://example.com/news/1",
      name: "Reuters",
      title: "Port disruption near the gulf corridor",
      latitude: 25.2,
      longitude: 55.3,
      published_at: 30.minutes.ago,
      fetched_at: 30.minutes.ago
    )

    Flight.create!(
      icao24: "abc123",
      latitude: 25.1,
      longitude: 55.4,
      updated_at: 1.minute.ago,
      military: true
    )

    TrainObservation.create!(
      external_id: "train-1",
      name: "IC 648",
      latitude: 25.15,
      longitude: 55.45,
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now
    )

    insight_snapshot = SnapshotStub.new(
      { insights: [{ title: "Flight surge", description: "Military aviation rose around the corridor.", severity: "high", lat: 25.1, lng: 55.4 }] },
      "ready"
    )
    situation_snapshot = SnapshotStub.new(
      { zones: [{ situation_name: "Hormuz pressure", theater: "Middle East", pulse_score: 72, story_count: 4, source_count: 6, lat: 25.3, lng: 55.5 }] },
      "ready"
    )
    chokepoint_snapshot = SnapshotStub.new(
      { chokepoints: [{ name: "Strait of Hormuz", status: "critical", ships_nearby: { total: 12 }, description: "Strategic tanker corridor", lat: 25.8, lng: 55.8 }] },
      "ready"
    )

    with_stubbed_fetch(InsightSnapshotService, insight_snapshot) do
      with_stubbed_fetch(ConflictPulseSnapshotService, situation_snapshot) do
        with_stubbed_fetch(ChokepointSnapshotService, chokepoint_snapshot) do
          get area_path(area)
        end
      end
    end

    assert_response :success
    assert_includes response.body, "Gulf monitor"
    assert_includes response.body, "Port disruption near the gulf corridor"
    assert_includes response.body, "Flight surge"
    assert_includes response.body, "Hormuz pressure"
    assert_includes response.body, "/#25.2500,55.2500,300000,0.000,-1.120;l:nw,in,fl;co:United Arab Emirates"
  end

  test "preset region area emits a region globe deeplink" do
    area = @user.area_workspaces.create!(
      name: "Gulf States",
      scope_type: "preset_region",
      profile: "maritime",
      bounds: { lamin: 21.0, lamax: 32.0, lomin: 44.0, lomax: 57.0 },
      scope_metadata: {
        region_key: "gulf-states",
        region_name: "Gulf States",
        camera: { lat: 27.0, lng: 50.0, height: 1_500_000, heading: 0, pitch: -0.85 },
      },
      default_layers: ["ships", "chokepoints", "news"]
    )

    with_empty_area_snapshots do
      get area_path(area)
    end

    assert_response :success
    assert_includes response.body, "/#27.0000,50.0000,1500000,0.000,-0.850;l:sh,cp,nw;r:gulf-states"
  end

  test "custom bbox area emits a circle deeplink" do
    area = @user.area_workspaces.create!(
      name: "Vienna Focus Area",
      scope_type: "bbox",
      profile: "general",
      bounds: { lamin: 47.8, lamax: 48.6, lomin: 15.7, lomax: 16.9 },
      scope_metadata: {
        center: { lat: 48.2, lng: 16.3 },
        radius_km: 50,
      },
      default_layers: ["trains", "railways", "news"]
    )

    with_empty_area_snapshots do
      get area_path(area)
    end

    assert_response :success
    assert_includes response.body, "/#48.2000,16.3000,300000,0.000,-1.120;l:tns,rl,nw;ci:48.2000,16.3000,50000"
  end

  test "index shows open on globe links for saved areas" do
    @user.area_workspaces.create!(
      name: "Austria",
      scope_type: "country_set",
      profile: "general",
      bounds: { lamin: 46.3, lamax: 49.1, lomin: 9.5, lomax: 17.2 },
      scope_metadata: { countries: ["Austria"] },
      default_layers: ["news", "trains"]
    )

    with_empty_area_snapshots do
      get areas_path
    end

    assert_response :success
    assert_includes response.body, "Open On Globe"
    assert_includes response.body, "co:Austria"
  end

  test "unauthenticated access redirects to login" do
    sign_out @user

    get areas_path

    assert_response :redirect
  end
end
