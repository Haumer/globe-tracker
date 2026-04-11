require "test_helper"

class OntologyV2InfrastructureImpactServiceTest < ActiveSupport::TestCase
  test "derives direct, nearby, and country-level infrastructure context for an event" do
    country = create_country
    place = OntologyEntity.create!(
      canonical_key: "place:kuwait",
      entity_type: "place",
      canonical_name: "Kuwait",
      metadata: { "latitude" => 29.3547, "longitude" => 47.9423, "geo_precision" => "point" }
    )
    port = TradeLocation.create!(
      locode: "KWKWI",
      country_code: "KW",
      country_code_alpha3: "KWT",
      country_name: "Kuwait",
      name: "Shuwaikh Port",
      location_kind: "port",
      latitude: 29.35,
      longitude: 47.93,
      status: "active",
      source: "test"
    )
    cable = SubmarineCable.create!(
      cable_id: "gulf-link",
      name: "Gulf Link",
      landing_points: [{ "country_code" => "KW", "country_name" => "Kuwait" }]
    )
    plant = PowerPlant.create!(
      gppd_idnr: "KW001",
      name: "Kuwait City Power Plant",
      country_code: "KW",
      country_name: "Kuwait",
      latitude: 29.356,
      longitude: 47.945,
      capacity_mw: 900,
      primary_fuel: "Gas"
    )
    evidence = create_story_cluster("cluster:kuwait-strike")
    event = create_event(place)
    OntologyEventEntity.create!(ontology_event: event, ontology_entity: country, role: "target", confidence: 0.8)
    OntologyEvidenceLink.create!(ontology_event: event, evidence: evidence, evidence_role: "primary_cluster", confidence: 0.9)

    OntologyV2IdentityService.sync
    OntologyV2AssetGraphService.sync
    result = OntologyV2InfrastructureImpactService.sync(now: Time.utc(2026, 4, 11, 12, 0, 0))

    port_entity = OntologyEntity.find_by!(canonical_key: "port:kwkwi")
    cable_entity = OntologyEntity.find_by!(canonical_key: "submarine-cable:gulf-link")
    plant_entity = OntologyEntity.find_by!(canonical_key: "power-plant:kw001")

    impacted_plant = OntologyRelationship.find_by!(
      source_node: event,
      target_node: plant_entity,
      relation_type: OntologyV2InfrastructureImpactService::IMPACTED_INFRASTRUCTURE
    )
    impacted_port = OntologyRelationship.find_by!(
      source_node: event,
      target_node: port_entity,
      relation_type: OntologyV2InfrastructureImpactService::IMPACTED_INFRASTRUCTURE
    )
    exposed_cable = OntologyRelationship.find_by!(
      source_node: event,
      target_node: cable_entity,
      relation_type: OntologyV2InfrastructureImpactService::EXPOSED_INFRASTRUCTURE
    )

    assert_operator result.fetch(:impact_relationships), :>=, 3
    [impacted_plant, impacted_port, exposed_cable].each do |relationship|
      assert_equal OntologyV2InfrastructureImpactService::DERIVED_BY, relationship.derived_by
      assert relationship.ontology_relationship_evidences.exists?(evidence: evidence, evidence_role: "event_primary_cluster")
    end
    assert_equal plant, plant_entity.ontology_entity_links.find_by!(role: "power_plant").linkable
    assert_equal cable, cable_entity.ontology_entity_links.find_by!(role: "submarine_cable").linkable
    assert_equal port, port_entity.ontology_entity_links.find_by!(role: "port").linkable
  end

  test "uses direct event roles for explicitly targeted infrastructure" do
    asset = OntologyEntity.create!(
      canonical_key: "port:manual-target",
      entity_type: "port",
      canonical_name: "Manual Target Port",
      metadata: { "latitude" => 10.0, "longitude" => 20.0 }
    )
    evidence = create_story_cluster("cluster:targeted-port")
    event = create_event(nil)
    OntologyEventEntity.create!(ontology_event: event, ontology_entity: asset, role: "target", confidence: 0.87)
    OntologyEvidenceLink.create!(ontology_event: event, evidence: evidence, evidence_role: "primary_cluster", confidence: 0.9)

    OntologyV2InfrastructureImpactService.sync

    relationship = OntologyRelationship.find_by!(
      source_node: event,
      target_node: asset,
      relation_type: OntologyV2InfrastructureImpactService::IMPACTED_INFRASTRUCTURE
    )

    assert_equal "direct_event_role", relationship.metadata["basis"]
    assert_equal "target", relationship.metadata["role"]
    assert relationship.ontology_relationship_evidences.exists?(evidence: evidence, evidence_role: "event_primary_cluster")
  end

  private

  def create_country
    OntologyEntity.create!(
      canonical_key: "country:kwt",
      entity_type: "country",
      canonical_name: "Kuwait",
      country_code: "KW",
      metadata: { "country_code_alpha3" => "KWT" }
    )
  end

  def create_event(place)
    OntologyEvent.create!(
      canonical_key: "event:kuwait-strike",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      place_entity: place,
      verification_status: "multi_source",
      geo_precision: place.present? ? "point" : "unknown",
      confidence: 0.82,
      geo_confidence: place.present? ? 0.8 : 0.0,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      metadata: { "canonical_title" => "Iran missile attack strikes Kuwait infrastructure" }
    )
  end

  def create_story_cluster(cluster_key)
    NewsStoryCluster.create!(
      cluster_key: cluster_key,
      canonical_title: "Iran missile attack strikes Kuwait infrastructure",
      content_scope: "core",
      event_family: "conflict",
      event_type: "missile_attack",
      geo_precision: "point",
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      verification_status: "multi_source"
    )
  end
end
