require "test_helper"

class InvestigationCasesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "cases@example.com", password: "password123")
    @other_user = User.create!(email: "analyst@example.com", password: "password123")
    sign_in @user
  end

  test "GET /cases/new preloads source object intake" do
    get new_case_path, params: {
      return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#10,20,300000",
      source_object: {
        object_kind: "theater",
        object_identifier: "Iran Theater",
        title: "Iran Theater",
        summary: "Regional pressure and corroborating signals",
        object_type: "theater",
        source_context: {
          severity: "high",
          pulse_score: "73",
        }
      }
    }

    assert_response :success
    assert_includes response.body, "Start a working case"
    assert_includes response.body, "Iran Theater"
    assert_includes response.body, "Create New Case"
    assert_includes response.body, "Add To Existing Case"
    assert_includes response.body, "Return To Globe"
    assert_includes response.body, "return_to"
  end

  test "POST /cases creates a case with a pinned source object and preserves globe return state" do
    post cases_path, params: {
      return_to: "/?focus_kind=chokepoint&focus_id=Strait%20of%20Hormuz#25.5,56.2,1400000",
      investigation_case: {
        title: "Hormuz monitoring",
        summary: "Track pressure on the corridor and supporting evidence.",
        status: "open",
        severity: "high",
        assignee_id: @other_user.id,
      },
      source_object: {
        object_kind: "chokepoint",
        object_identifier: "Strait of Hormuz",
        title: "Strait of Hormuz",
        summary: "Strategic energy corridor",
        object_type: "corridor",
        latitude: "26.56",
        longitude: "56.27",
        source_context: {
          relationship_count: "2",
          evidence_count: "4",
          membership_count: "0",
        }
      }
    }

    investigation_case = InvestigationCase.order(:id).last
    assert_redirected_to case_path(investigation_case, return_to: "/?focus_kind=chokepoint&focus_id=Strait%20of%20Hormuz#25.5,56.2,1400000")
    assert_equal "Hormuz monitoring", investigation_case.title
    assert_equal "high", investigation_case.severity
    assert_equal @other_user, investigation_case.assignee
    assert_equal 1, investigation_case.case_objects.count
    assert_equal "Strait of Hormuz", investigation_case.case_objects.first.title
  end

  test "GET /cases/:id shows pinned objects and notes" do
    investigation_case = @user.investigation_cases.create!(
      title: "Iran theater watch",
      status: "monitoring",
      severity: "critical",
      summary: "Track theater escalation and regional chokepoint pressure."
    )
    investigation_case.case_objects.create!(
      object_kind: "theater",
      object_identifier: "Iran Theater",
      title: "Iran Theater",
      summary: "Derived conflict theater bubble",
      object_type: "theater"
    )
    investigation_case.case_notes.create!(user: @user, body: "Start with Hormuz, Bahrain, and Suez.")

    get case_path(investigation_case), params: { return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#12,43,1200000" }

    assert_response :success
    assert_includes response.body, "Iran theater watch"
    assert_includes response.body, "Pinned Objects"
    assert_includes response.body, "Iran Theater"
    assert_includes response.body, "Start with Hormuz, Bahrain, and Suez."
    assert_includes response.body, "Add Note"
    assert_includes response.body, "Return To Globe"
  end

  test "GET /cases/:id renders the primary dossier workspace when durable context is available" do
    investigation_case = @user.investigation_cases.create!(
      title: "Hormuz deep dive",
      status: "monitoring",
      severity: "high",
      summary: "Track the theater, chokepoint pressure, and supporting evidence."
    )
    investigation_case.case_objects.create!(
      object_kind: "theater",
      object_identifier: "Iran Theater",
      title: "Iran Theater",
      summary: "Regional pressure and corroborating signals",
      object_type: "theater",
      source_context: { "pulse_score" => 81, "escalation_trend" => "escalating" }
    )
    investigation_case.case_notes.create!(user: @user, kind: "brief", body: "Analyst brief captured for the morning shift.")

    theater = OntologyEntity.create!(
      canonical_key: "theater:iran-theater",
      entity_type: "theater",
      canonical_name: "Iran Theater",
      metadata: { "cluster_count" => 4, "total_sources" => 11, "situation_names" => ["Hormuz", "Gulf States"] }
    )
    actor = OntologyEntity.create!(
      canonical_key: "country:irn",
      entity_type: "country",
      canonical_name: "Iran"
    )
    hormuz = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:hormuz",
      entity_type: "corridor",
      canonical_name: "Strait of Hormuz",
      metadata: { "description" => "Strategic energy corridor" }
    )
    cluster = create_story_cluster("cluster:hormuz", "Shipping pressure builds around Hormuz")

    OntologyRelationship.create!(
      source_node: actor,
      target_node: theater,
      relation_type: "participant_in",
      confidence: 0.88,
      fresh_until: 2.hours.from_now,
      derived_by: "test",
      explanation: "Iran is a participant in the theater"
    )

    OntologyRelationship.create!(
      source_node: theater,
      target_node: hormuz,
      relation_type: "theater_pressure",
      confidence: 0.93,
      fresh_until: 2.hours.from_now,
      derived_by: "test",
      explanation: "Iran Theater is exerting pressure on Strait of Hormuz"
    ).tap do |relationship|
      OntologyRelationshipEvidence.create!(
        ontology_relationship: relationship,
        evidence: cluster,
        evidence_role: "local_story",
        confidence: 0.84
      )
    end

    zone = {
      theater: "Iran Theater",
      cell_key: "25,55",
      situation_name: "Strait of Hormuz",
      pulse_score: 81,
      escalation_trend: "escalating",
      count_24h: 31,
      source_count: 16,
      story_count: 5,
      spike_ratio: 4.9,
      avg_tone: -2.8,
      cross_layer_signals: { military_flights: 8 },
      top_articles: [
        {
          title: "Shipping pressure builds around Hormuz",
          publisher: "Example Wire",
          published_at: 45.minutes.ago.iso8601,
          cluster_id: cluster.cluster_key,
        },
      ],
      top_headlines: ["Shipping pressure builds around Hormuz"],
      detected_at: 20.minutes.ago.iso8601,
    }

    LayerSnapshot.create!(
      snapshot_type: ConflictPulseSnapshotService::SNAPSHOT_TYPE,
      scope_key: ConflictPulseSnapshotService::SCOPE_KEY,
      status: "ready",
      payload: { zones: [zone], strategic_situations: [], strike_arcs: [], hex_cells: [] },
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now,
    )

    LayerSnapshot.create!(
      snapshot_type: TheaterBriefService::SNAPSHOT_TYPE,
      scope_key: TheaterBriefService.scope_key_for(zone),
      status: "ready",
      payload: {
        brief: {
          assessment: "Escalation pressure remains elevated around the theater, with reporting concentrated on chokepoint risk and follow-on military signaling.",
          why_we_believe_it: [
            "31 reports in the last 24 hours are carrying the theater.",
            "16 sources are contributing to the current read."
          ],
          key_developments: [
            "Shipping pressure builds around Hormuz",
            "Iran posture remains elevated in the latest reporting"
          ],
          watch_next: [
            "Watch whether fresh reporting pushes above the current pace."
          ],
          confidence_level: "high",
          confidence_rationale: "Multiple recent sources support the current escalation read.",
        },
      },
      metadata: {
        provider: "test",
        model: "stub",
        source_context: {
          theater: zone[:theater],
          situation_name: zone[:situation_name],
          pulse_score: zone[:pulse_score],
          escalation_trend: zone[:escalation_trend],
          reports_24h: zone[:count_24h],
          sources: zone[:source_count],
          stories: zone[:story_count],
          spike_ratio: zone[:spike_ratio],
        },
      },
      fetched_at: 45.minutes.ago,
    )

    get case_path(investigation_case), params: { return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#12,43,1200000" }

    assert_response :success
    assert_includes response.body, "Operational Assessment"
    assert_includes response.body, "Primary Focus"
    assert_includes response.body, "Latest Developments"
    assert_includes response.body, "Durable Graph"
    assert_includes response.body, "Case Timeline"
    assert_includes response.body, "Stored AI brief"
    assert_includes response.body, "Shipping pressure builds around Hormuz"
    assert_includes response.body, "Strait of Hormuz"
  end

  test "GET /cases/:id surfaces nearby supporting signals in the case workspace" do
    investigation_case = @user.investigation_cases.create!(
      title: "Hormuz strike watch",
      status: "monitoring",
      severity: "high",
      summary: "Track lagging strike corroboration around the theater."
    )
    investigation_case.case_objects.create!(
      object_kind: "theater",
      object_identifier: "Iran Theater",
      title: "Iran Theater",
      summary: "Regional pressure and corroborating signals",
      object_type: "theater",
      latitude: 26.55,
      longitude: 56.3,
      source_context: { "pulse_score" => 81, "escalation_trend" => "escalating" }
    )

    FireHotspot.create!(
      external_id: "strike-near-001",
      latitude: 26.7,
      longitude: 56.45,
      brightness: 348.0,
      confidence: "high",
      satellite: "Aqua",
      instrument: "MODIS",
      frp: 58.2,
      daynight: "N",
      acq_datetime: 18.hours.ago,
      fetched_at: Time.current
    )
    FireHotspot.create!(
      external_id: "strike-old-001",
      latitude: 26.65,
      longitude: 56.33,
      brightness: 342.0,
      confidence: "high",
      satellite: "Terra",
      instrument: "MODIS",
      frp: 42.0,
      daynight: "D",
      acq_datetime: 9.days.ago,
      fetched_at: Time.current
    )
    FireHotspot.create!(
      external_id: "strike-far-001",
      latitude: 7.1,
      longitude: 4.2,
      brightness: 360.0,
      confidence: "high",
      satellite: "NOAA-21",
      instrument: "VIIRS",
      frp: 64.3,
      daynight: "N",
      acq_datetime: 12.hours.ago,
      fetched_at: Time.current
    )

    get case_path(investigation_case)

    assert_response :success
    assert_includes response.body, "Supporting Signals"
    assert_includes response.body, "Thermal Detections"
    assert_includes response.body, "Raw satellite fire/heat detections"
    assert_includes response.body, "Thermal detection"
    assert_includes response.body, "Aqua"
    assert_not_includes response.body, "No nearby supporting signals are in the current 7-day nearby scope."
  end

  test "GET /cases/:id renders resource context for pipeline focuses" do
    Pipeline.create!(
      pipeline_id: "pipe-001",
      name: "Nord Stream 1",
      pipeline_type: "gas",
      status: "operational",
      length_km: 1224,
      country: "Germany"
    )

    investigation_case = @user.investigation_cases.create!(
      title: "Pipeline pressure watch",
      status: "monitoring",
      severity: "medium",
      summary: "Track flow risk against strategic energy infrastructure."
    )
    investigation_case.case_objects.create!(
      object_kind: "pipeline",
      object_identifier: "pipe-001",
      title: "Nord Stream 1",
      summary: "Strategic gas corridor",
      object_type: "gas",
      latitude: 54.1,
      longitude: 12.1
    )

    get case_path(investigation_case)

    assert_response :success
    assert_includes response.body, "Resource Context"
    assert_includes response.body, "Resource carrier"
    assert_includes response.body, "Gas"
    assert_includes response.body, "1,224 km"
  end

  test "PATCH /cases/:id updates status severity and assignee while preserving globe return state" do
    investigation_case = @user.investigation_cases.create!(
      title: "Iran theater watch",
      status: "open",
      severity: "medium",
      assignee: @user
    )

    patch case_path(investigation_case), params: {
      return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#12,43,1200000",
      investigation_case: {
        status: "escalated",
        severity: "critical",
        assignee_id: @other_user.id,
        summary: "Move to active escalation tracking."
      }
    }

    assert_redirected_to case_path(investigation_case, return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#12,43,1200000")
    investigation_case.reload
    assert_equal "escalated", investigation_case.status
    assert_equal "critical", investigation_case.severity
    assert_equal @other_user, investigation_case.assignee
    assert_equal "Move to active escalation tracking.", investigation_case.summary
  end

  def create_story_cluster(key, title)
    NewsStoryCluster.create!(
      cluster_key: key,
      canonical_title: title,
      content_scope: "core",
      event_family: "conflict",
      event_type: "military_activity",
      location_name: "Hormuz",
      latitude: 26.7,
      longitude: 56.4,
      geo_precision: "point",
      first_seen_at: 1.hour.ago,
      last_seen_at: 20.minutes.ago,
      article_count: 3,
      source_count: 3,
      cluster_confidence: 0.84,
      verification_status: "multi_source",
      source_reliability: 0.78,
      geo_confidence: 0.82
    )
  end
end
