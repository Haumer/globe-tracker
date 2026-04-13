require "test_helper"

class SituationAssessmentServiceTest < ActiveSupport::TestCase
  test "builds ontology-backed assessment for a chokepoint with reporting and operational evidence" do
    travel_to Time.utc(2026, 4, 11, 12, 0, 0) do
      theater = OntologyEntity.create!(
        canonical_key: "theater:test-theater",
        entity_type: "theater",
        canonical_name: "Test Theater"
      )
      hormuz = OntologyEntity.create!(
        canonical_key: "corridor:chokepoint:hormuz",
        entity_type: "corridor",
        canonical_name: "Strait of Hormuz",
        metadata: { "latitude" => 26.56, "longitude" => 56.27 }
      )
      flight_entity = OntologyEntity.create!(
        canonical_key: "asset:flight:icao24:abc123",
        entity_type: "asset",
        canonical_name: "RCH432",
        metadata: { "asset_kind" => "flight", "military" => true }
      )
      flight = Flight.create!(
        icao24: "abc123",
        callsign: "RCH432",
        latitude: 26.2,
        longitude: 56.3,
        source: "adsb",
        military: true,
        updated_at: 5.minutes.ago
      )
      cluster = create_story_cluster(
        key: "cluster:hormuz-pressure",
        title: "Shipping pressure builds around the Strait of Hormuz"
      )

      pressure = OntologyRelationship.create!(
        source_node: theater,
        target_node: hormuz,
        relation_type: "theater_pressure",
        confidence: 0.9,
        fresh_until: 2.hours.from_now,
        derived_by: "test",
        explanation: "Test Theater is exerting pressure on Strait of Hormuz"
      )
      OntologyRelationshipEvidence.create!(
        ontology_relationship: pressure,
        evidence: cluster,
        evidence_role: "local_story",
        confidence: 0.82
      )

      operational = OntologyRelationship.create!(
        source_node: flight_entity,
        target_node: hormuz,
        relation_type: "operational_activity",
        confidence: 0.86,
        fresh_until: 30.minutes.from_now,
        derived_by: "test",
        explanation: "RCH432 is operating near Strait of Hormuz activity"
      )
      OntologyRelationshipEvidence.create!(
        ontology_relationship: operational,
        evidence: flight,
        evidence_role: "tracked_asset",
        confidence: 0.81
      )

      assessment = SituationAssessmentService.for_node(kind: "chokepoint", id: "hormuz")

      assert_equal "corridor_exposure", assessment[:situation_type]
      assert_equal "Strait of Hormuz", assessment[:title]
      assert_operator assessment[:confidence], :>=, 70
      assert_operator assessment[:coverage_quality], :>=, 70
      assert_includes assessment[:reported].join(" "), "Shipping pressure builds"
      assert_includes assessment[:observed].join(" "), "RCH432 is operating"
      assert_includes assessment[:inferred].join(" "), "Test Theater is exerting pressure"
      refute_includes assessment[:missing_data], "No live operational evidence attached"
      assert_equal %w[theater_pressure operational_activity].sort, assessment[:affected_entities].map { |item| item[:relation_type] }.sort
    end
  end

  test "calls out missing evidence for a thin ontology node" do
    OntologyEntity.create!(
      canonical_key: "country:test",
      entity_type: "country",
      canonical_name: "Testland"
    )

    assessment = SituationAssessmentService.for_node(kind: "entity", id: "country:test")

    assert_equal "supply_chain_exposure", assessment[:situation_type]
    assert_includes assessment[:missing_data], "No active graph relationships attached to this node"
    assert_includes assessment[:missing_data], "No direct reporting evidence attached"
    assert_includes assessment[:missing_data], "No live operational evidence attached"
    assert_includes assessment[:missing_data], "No evidence links attached to this node"
    assert_operator assessment[:confidence], :<, 30
  end

  test "recent promotes durable ontology nodes and skips transient tracked assets" do
    country = OntologyEntity.create!(
      canonical_key: "country:test",
      entity_type: "country",
      canonical_name: "Testland"
    )
    flight_entity = OntologyEntity.create!(
      canonical_key: "asset:flight:icao24:abc123",
      entity_type: "asset",
      canonical_name: "RCH432",
      metadata: { "asset_kind" => "flight", "military" => true }
    )
    flight = Flight.create!(
      icao24: "abc123",
      callsign: "RCH432",
      latitude: 26.2,
      longitude: 56.3,
      source: "adsb",
      military: true,
      updated_at: 5.minutes.ago
    )
    relationship = OntologyRelationship.create!(
      source_node: flight_entity,
      target_node: country,
      relation_type: "operational_activity",
      confidence: 0.91,
      fresh_until: 30.minutes.from_now,
      derived_by: "test",
      explanation: "RCH432 is operating near Testland"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: flight,
      evidence_role: "tracked_asset",
      confidence: 0.84
    )

    assessments = SituationAssessmentService.recent(limit: 5)

    assert_equal ["Testland"], assessments.map { |assessment| assessment[:title] }
    assert_equal ["supply_chain_exposure"], assessments.map { |assessment| assessment[:situation_type] }
    assert_includes assessments.first[:observed].join(" "), "RCH432 is operating"
  end

  test "classifies hazard-exposed infrastructure as infrastructure exposure" do
    travel_to Time.utc(2026, 4, 11, 12, 0, 0) do
      Earthquake.create!(
        external_id: "eq-assessment-1",
        title: "M6.3 earthquake near the industrial coast",
        magnitude: 6.3,
        magnitude_type: "mww",
        latitude: 24.90,
        longitude: 54.95,
        depth: 10.0,
        event_time: 15.minutes.ago,
        tsunami: false,
        alert: "yellow",
        fetched_at: Time.current
      )
      plant = PowerPlant.create!(
        gppd_idnr: "AE-ASSESSMENT-1",
        name: "Jebel Ali Assessment Gas Plant",
        country_code: "AE",
        country_name: "United Arab Emirates",
        latitude: 24.96,
        longitude: 55.02,
        capacity_mw: 780,
        primary_fuel: "Gas"
      )

      OntologyRelationshipSyncService.sync_recent

      assessment = SituationAssessmentService.for_node(kind: "entity", id: "power-plant:ae-assessment-1")

      assert_equal "infrastructure_exposure", assessment[:situation_type]
      assert_includes assessment[:observed].join(" "), "M6.3 earthquake near the industrial coast"
      assert_includes assessment[:inferred].join(" "), plant.name
      assert_includes assessment[:evidence].map { |item| item[:type] }, "earthquake"
      refute_includes assessment[:missing_data], "No live operational evidence attached"

      recent = SituationAssessmentService.recent(limit: 5)
      assert_equal "infrastructure_exposure", recent.first[:situation_type]
      assert_includes recent.first[:title], "M6.3 earthquake"
    end
  end

  test "classifies v2 impacted infrastructure relationships as disruptions" do
    asset = OntologyEntity.create!(
      canonical_key: "port:v2-impact",
      entity_type: "port",
      canonical_name: "V2 Impact Port"
    )
    event = OntologyEvent.create!(
      canonical_key: "event:v2-impact",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      verification_status: "multi_source",
      geo_precision: "unknown",
      metadata: { "canonical_title" => "Strike damages V2 Impact Port" }
    )
    OntologyRelationship.create!(
      source_node: event,
      target_node: asset,
      relation_type: OntologyV2InfrastructureImpactService::IMPACTED_INFRASTRUCTURE,
      confidence: 0.84,
      derived_by: OntologyV2InfrastructureImpactService::DERIVED_BY,
      explanation: "Strike damages V2 Impact Port."
    )

    assessment = SituationAssessmentService.for_node(kind: "entity", id: "port:v2-impact")

    assert_equal "infrastructure_disruption", assessment[:situation_type]
    assert_includes assessment[:observed].join(" "), "Strike damages V2 Impact Port"
    assert_includes assessment[:watch_next].join(" "), "event graph"
  end

  test "country assessment leads with recent state actor events instead of static asset inventory" do
    country = OntologyEntity.create!(
      canonical_key: "country:irn",
      entity_type: "country",
      canonical_name: "Iran",
      country_code: "IR",
      metadata: { "country_code_alpha3" => "IRN" }
    )
    actor = OntologyEntity.create!(
      canonical_key: "actor:state:ir",
      entity_type: "actor",
      canonical_name: "Iran",
      country_code: "IR"
    )
    event = OntologyEvent.create!(
      canonical_key: "event:iran-negotiation-pressure",
      event_family: "conflict",
      event_type: "ceasefire",
      status: "active",
      verification_status: "multi_source",
      geo_precision: "unknown",
      confidence: 0.82,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      metadata: { "canonical_title" => "Iran ceasefire talks under pressure" }
    )
    adjacent_event = OntologyEvent.create!(
      canonical_key: "event:adjacent-iran-threat",
      event_family: "diplomacy",
      event_type: "negotiation",
      status: "active",
      verification_status: "multi_source",
      geo_precision: "unknown",
      confidence: 0.9,
      first_seen_at: Time.utc(2026, 4, 11, 11, 50, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 5, 0),
      metadata: { "canonical_title" => "Adjacent Iran threat commentary", "content_scope" => "adjacent" }
    )
    asset = OntologyEntity.create!(
      canonical_key: "port:static-iran-port",
      entity_type: "port",
      canonical_name: "Static Iran Port"
    )
    OntologyRelationship.create!(
      source_node: actor,
      target_node: country,
      relation_type: OntologyV2IdentityService::REPRESENTS_COUNTRY,
      confidence: 0.95,
      derived_by: OntologyV2IdentityService::DERIVED_BY
    )
    OntologyRelationship.create!(
      source_node: actor,
      target_node: event,
      relation_type: "participated_in_event",
      confidence: 0.84,
      derived_by: OntologyV2EventGraphService::DERIVED_BY,
      explanation: "Iran is participating in Iran ceasefire talks under pressure."
    )
    OntologyRelationship.create!(
      source_node: actor,
      target_node: adjacent_event,
      relation_type: "participated_in_event",
      confidence: 0.95,
      derived_by: OntologyV2EventGraphService::DERIVED_BY,
      explanation: "Iran is participating in adjacent Iran threat commentary."
    )
    OntologyRelationship.create!(
      source_node: asset,
      target_node: country,
      relation_type: OntologyV2AssetGraphService::LOCATED_IN_COUNTRY,
      confidence: 0.99,
      derived_by: OntologyV2AssetGraphService::DERIVED_BY,
      explanation: "Static Iran Port is located in country Iran."
    )

    assessment = SituationAssessmentService.for_node(kind: "entity", id: "country:irn", now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_equal "conflict_report", assessment[:situation_type]
    assert_includes assessment[:inferred].join(" "), "Iran ceasefire talks under pressure"
    refute_includes assessment[:inferred].join(" "), "Static Iran Port"
    refute_includes assessment[:inferred].join(" "), "adjacent Iran threat"
    assert_equal "participated_in_event", assessment[:relationships].first[:relation_type]
    assert_equal "Iran", assessment[:relationships].first.dig(:via_node, :name)
  end

  private

  def create_story_cluster(key:, title:)
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
