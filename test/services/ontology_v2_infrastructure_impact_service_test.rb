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

    exposed_plant = OntologyRelationship.find_by!(
      source_node: event,
      target_node: plant_entity,
      relation_type: OntologyV2InfrastructureImpactService::EXPOSED_INFRASTRUCTURE
    )
    exposed_port = OntologyRelationship.find_by!(
      source_node: event,
      target_node: port_entity,
      relation_type: OntologyV2InfrastructureImpactService::EXPOSED_INFRASTRUCTURE
    )
    exposed_cable = OntologyRelationship.find_by!(
      source_node: event,
      target_node: cable_entity,
      relation_type: OntologyV2InfrastructureImpactService::EXPOSED_INFRASTRUCTURE
    )

    assert_operator result.fetch(:impact_relationships), :>=, 3
    [exposed_plant, exposed_port, exposed_cable].each do |relationship|
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

  test "promotes nearby infrastructure to impact only when the asset is directly referenced" do
    place = OntologyEntity.create!(
      canonical_key: "place:shuwaikh",
      entity_type: "place",
      canonical_name: "Shuwaikh",
      metadata: { "latitude" => 29.3547, "longitude" => 47.9423, "geo_precision" => "point" }
    )
    port = TradeLocation.create!(
      locode: "KWSWK",
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
    event = OntologyEvent.create!(
      canonical_key: "event:shuwaikh-port-strike",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      place_entity: place,
      verification_status: "multi_source",
      geo_precision: "point",
      confidence: 0.82,
      geo_confidence: 0.8,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      metadata: { "canonical_title" => "Missile attack hits Shuwaikh Port" }
    )
    evidence = create_story_cluster("cluster:shuwaikh-port-strike")
    OntologyEvidenceLink.create!(ontology_event: event, evidence: evidence, evidence_role: "primary_cluster", confidence: 0.9)

    OntologyV2AssetGraphService.sync
    OntologyV2InfrastructureImpactService.sync_batch(now: Time.utc(2026, 4, 11, 12, 0, 0))

    port_entity = OntologyEntity.find_by!(canonical_key: "port:kwswk")
    relationship = OntologyRelationship.find_by!(
      source_node: event,
      target_node: port_entity,
      relation_type: OntologyV2InfrastructureImpactService::IMPACTED_INFRASTRUCTURE
    )

    assert_equal "direct_asset_reference", relationship.metadata["basis"]
    assert_includes relationship.explanation, "directly references"
    assert_equal port, port_entity.ontology_entity_links.find_by!(role: "port").linkable
  end

  test "sync batch processes only the requested recent event window" do
    asset = OntologyEntity.create!(
      canonical_key: "port:batch-target",
      entity_type: "port",
      canonical_name: "Batch Target Port",
      metadata: { "latitude" => 10.0, "longitude" => 20.0 }
    )
    first = create_event(nil)
    second = OntologyEvent.create!(
      canonical_key: "event:second-batch-target",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      verification_status: "multi_source",
      geo_precision: "unknown",
      confidence: 0.82,
      first_seen_at: Time.utc(2026, 4, 11, 11, 46, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 1, 0),
      metadata: { "canonical_title" => "Second target event" }
    )
    OntologyEventEntity.create!(ontology_event: first, ontology_entity: asset, role: "target")
    OntologyEventEntity.create!(ontology_event: second, ontology_entity: asset, role: "target")

    result = OntologyV2InfrastructureImpactService.sync_batch(batch_size: 1, now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_equal 1, result.fetch(:records_fetched)
    assert_equal first.id, result.fetch(:next_cursor)
    assert_not result.fetch(:complete)
    assert OntologyRelationship.exists?(source_node: first, target_node: asset, relation_type: OntologyV2InfrastructureImpactService::IMPACTED_INFRASTRUCTURE)
    assert_not OntologyRelationship.exists?(source_node: second, target_node: asset, relation_type: OntologyV2InfrastructureImpactService::IMPACTED_INFRASTRUCTURE)
  end

  test "does not turn ceasefire reporting near an asset into impact" do
    place = OntologyEntity.create!(
      canonical_key: "place:tehran",
      entity_type: "place",
      canonical_name: "Tehran",
      metadata: { "latitude" => 35.7, "longitude" => 51.4, "geo_precision" => "point" }
    )
    asset = OntologyEntity.create!(
      canonical_key: "power-plant:tehran-test",
      entity_type: "power_plant",
      canonical_name: "Tehran Test Plant",
      metadata: { "latitude" => 35.705, "longitude" => 51.405 }
    )
    event = OntologyEvent.create!(
      canonical_key: "event:ceasefire-with-strikes-title",
      event_family: "conflict",
      event_type: "ceasefire",
      status: "active",
      place_entity: place,
      verification_status: "multi_source",
      geo_precision: "point",
      geo_confidence: 0.9,
      confidence: 0.82,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      metadata: { "canonical_title" => "Iran ceasefire under pressure as strikes continue" }
    )

    OntologyV2InfrastructureImpactService.sync_batch(now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_not OntologyRelationship.exists?(source_node: event, target_node: asset, derived_by: OntologyV2InfrastructureImpactService::DERIVED_BY)
  end

  test "ignores publisher-like locations for proximity impact" do
    NewsSource.create!(
      canonical_key: "source:the-washington-post",
      name: "The Washington Post",
      source_kind: "publisher",
      publisher_domain: "washingtonpost.com"
    )
    place = OntologyEntity.create!(
      canonical_key: "place:washington-post",
      entity_type: "place",
      canonical_name: "Washington Post",
      metadata: { "latitude" => 35.7, "longitude" => 51.4, "geo_precision" => "point" }
    )
    asset = OntologyEntity.create!(
      canonical_key: "military-base:publisher-location-test",
      entity_type: "military_base",
      canonical_name: "Publisher Location Test Base",
      metadata: { "latitude" => 35.701, "longitude" => 51.401 }
    )
    event = OntologyEvent.create!(
      canonical_key: "event:publisher-location-strike",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      place_entity: place,
      verification_status: "multi_source",
      geo_precision: "point",
      geo_confidence: 0.9,
      confidence: 0.82,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      metadata: { "canonical_title" => "Missile attack report", "location_name" => "Washington Post" }
    )

    OntologyV2InfrastructureImpactService.sync_batch(now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_not OntologyRelationship.exists?(source_node: event, target_node: asset, derived_by: OntologyV2InfrastructureImpactService::DERIVED_BY)
  end

  test "prefers cluster coordinates over stale publisher place coordinates" do
    NewsSource.create!(
      canonical_key: "source:pbs",
      name: "PBS",
      source_kind: "publisher",
      publisher_domain: "pbs.org"
    )
    publisher_place = OntologyEntity.create!(
      canonical_key: "place:pbs-newshour",
      entity_type: "place",
      canonical_name: "PBS NewsHour",
      metadata: { "latitude" => 50.8, "longitude" => 4.4, "geo_precision" => "point" }
    )
    belgian_asset = OntologyEntity.create!(
      canonical_key: "power-plant:belgium-stale-place",
      entity_type: "power_plant",
      canonical_name: "Belgium Stale Place Plant",
      metadata: { "latitude" => 50.81, "longitude" => 4.41 }
    )
    afghan_asset = OntologyEntity.create!(
      canonical_key: "airport:kabul-cluster-coordinate",
      entity_type: "airport",
      canonical_name: "Kabul Cluster Coordinate Airport",
      metadata: { "latitude" => 34.52, "longitude" => 69.19 }
    )
    cluster = NewsStoryCluster.create!(
      cluster_key: "cluster:afghanistan-earthquake",
      canonical_title: "5.8 magnitude earthquake hits Afghanistan and Pakistan, killing 8 on outskirts of Kabul",
      content_scope: "core",
      event_family: "disaster",
      event_type: "earthquake",
      location_name: "PBS NewsHour",
      latitude: 34.515,
      longitude: 69.185,
      geo_precision: "point",
      geo_confidence: 0.82,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      verification_status: "multi_source"
    )
    event = OntologyEvent.create!(
      canonical_key: "event:afghanistan-earthquake",
      event_family: "disaster",
      event_type: "earthquake",
      status: "active",
      place_entity: publisher_place,
      primary_story_cluster: cluster,
      verification_status: "multi_source",
      geo_precision: "point",
      geo_confidence: 0.82,
      confidence: 0.82,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      metadata: {
        "canonical_title" => "5.8 magnitude earthquake hits Afghanistan and Pakistan, killing 8 on outskirts of Kabul",
        "location_name" => "PBS NewsHour",
      }
    )

    OntologyV2InfrastructureImpactService.sync_batch(now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_not OntologyRelationship.exists?(source_node: event, target_node: belgian_asset, derived_by: OntologyV2InfrastructureImpactService::DERIVED_BY)
    assert OntologyRelationship.exists?(source_node: event, target_node: afghan_asset, derived_by: OntologyV2InfrastructureImpactService::DERIVED_BY)
  end

  test "does not use publisher-labeled cluster coordinates for conflict proximity" do
    NewsSource.create!(
      canonical_key: "source:euronews",
      name: "EuroNews",
      source_kind: "publisher",
      publisher_domain: "euronews.com"
    )
    publisher_place = OntologyEntity.create!(
      canonical_key: "place:euronews",
      entity_type: "place",
      canonical_name: "EuroNews",
      metadata: { "latitude" => 50.4, "longitude" => 30.5, "geo_precision" => "point" }
    )
    nearby_asset = OntologyEntity.create!(
      canonical_key: "military-base:publisher-labeled-conflict",
      entity_type: "military_base",
      canonical_name: "Publisher Labeled Conflict Base",
      metadata: { "latitude" => 50.401, "longitude" => 30.501 }
    )
    cluster = NewsStoryCluster.create!(
      cluster_key: "cluster:publisher-labeled-conflict",
      canonical_title: "Ukraine’s Zhytomyr region reels after missile and drone strike",
      content_scope: "core",
      event_family: "conflict",
      event_type: "missile_attack",
      location_name: "EuroNews",
      latitude: 50.4,
      longitude: 30.5,
      geo_precision: "point",
      geo_confidence: 0.82,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      verification_status: "multi_source"
    )
    event = OntologyEvent.create!(
      canonical_key: "event:publisher-labeled-conflict",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      place_entity: publisher_place,
      primary_story_cluster: cluster,
      verification_status: "multi_source",
      geo_precision: "point",
      geo_confidence: 0.82,
      confidence: 0.82,
      first_seen_at: Time.utc(2026, 4, 11, 11, 45, 0),
      last_seen_at: Time.utc(2026, 4, 11, 12, 0, 0),
      metadata: {
        "canonical_title" => "Ukraine’s Zhytomyr region reels after missile and drone strike",
        "location_name" => "EuroNews",
      }
    )

    OntologyV2InfrastructureImpactService.sync_batch(now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_not OntologyRelationship.exists?(source_node: event, target_node: nearby_asset, derived_by: OntologyV2InfrastructureImpactService::DERIVED_BY)
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
