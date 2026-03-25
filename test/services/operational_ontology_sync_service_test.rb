require "test_helper"

class OperationalOntologySyncServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
    OperationalOntologySyncService.instance_variable_set(:@recent_enqueue_slots, {})
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    Rails.cache.clear
    OperationalOntologySyncService.instance_variable_set(:@recent_enqueue_slots, {})
  end

  test "syncs flights into asset entities" do
    flight = Flight.create!(
      icao24: "abc123",
      callsign: "BAW123",
      origin_country: "United Kingdom",
      source: "opensky",
      military: false,
      category: "A3",
      registration: "G-TEST",
      aircraft_type: "A320",
      latitude: 51.47,
      longitude: -0.45
    )

    entity = OperationalOntologySyncService.sync_flight(flight)

    assert_equal "asset", entity.entity_type
    assert_equal "BAW123", entity.canonical_name
    assert_equal "GB", entity.country_code
    assert_equal "flight", entity.metadata["asset_kind"]
    assert OntologyEntityAlias.exists?(ontology_entity: entity, name: "BAW123")
    assert OntologyEntityLink.exists?(ontology_entity: entity, linkable: flight, role: "tracked_flight")
  end

  test "syncs ships into asset entities" do
    ship = Ship.create!(
      mmsi: "123456789",
      name: "MSC Example",
      ship_type: 70,
      destination: "Piraeus",
      flag: "GR",
      latitude: 37.94,
      longitude: 23.64
    )

    entity = OperationalOntologySyncService.sync_ship(ship)

    assert_equal "asset", entity.entity_type
    assert_equal "MSC Example", entity.canonical_name
    assert_equal "ship", entity.metadata["asset_kind"]
    assert OntologyEntityAlias.exists?(ontology_entity: entity, name: "123456789")
    assert OntologyEntityLink.exists?(ontology_entity: entity, linkable: ship, role: "tracked_ship")
  end

  test "syncs outages into ontology events and affected entities" do
    outage = InternetOutage.create!(
      external_id: "cf:ir:20260325-1",
      entity_type: "country",
      entity_code: "IR",
      entity_name: "Iran",
      datasource: "cloudflare",
      score: 78.0,
      level: "high",
      condition: "disruption",
      started_at: Time.utc(2026, 3, 25, 9, 0, 0),
      fetched_at: Time.utc(2026, 3, 25, 9, 5, 0)
    )

    event = OperationalOntologySyncService.sync_outage(outage)
    affected_entity = event.ontology_event_entities.first.ontology_entity

    assert_equal "infrastructure", event.event_family
    assert_equal "outage", event.event_type
    assert_equal "active", event.status
    assert_equal "country", event.geo_precision
    assert_in_delta 0.78, event.confidence, 0.001
    assert_equal "place", affected_entity.entity_type
    assert_equal "Iran", affected_entity.canonical_name
    assert OntologyEntityLink.exists?(ontology_entity: affected_entity, linkable: outage, role: "affected_entity")
    assert OntologyEvidenceLink.exists?(ontology_event: event, evidence: outage, evidence_role: "outage_record")
  end

  test "enqueue_backfill schedules all operational targets" do
    OperationalOntologySyncService.enqueue_backfill(batch_size: 10)

    jobs = enqueued_jobs.select { |job| job[:job] == OperationalOntologyBatchJob }
    targets = jobs.map { |job| job[:args].first }

    assert_equal 3, jobs.size
    assert_includes targets, "flights"
    assert_includes targets, "ships"
    assert_includes targets, "outages"
  end

  test "enqueue_recent coalesces jobs within the throttle window" do
    now = Time.zone.parse("2026-03-25 12:00:00 UTC")

    assert OperationalOntologySyncService.enqueue_recent("flights", now: now)
    refute OperationalOntologySyncService.enqueue_recent("flights", now: now + 1.minute)

    jobs = enqueued_jobs.select { |job| job[:job] == OperationalOntologyBatchJob }
    assert_equal 1, jobs.size
    assert_equal "flights", jobs.first[:args].first
  end

  test "sync_outage replaces stale affected entity memberships" do
    outage = InternetOutage.create!(
      external_id: "cf:ir:20260325-2",
      entity_type: "country",
      entity_code: "IR",
      entity_name: "Iran",
      datasource: "cloudflare",
      score: 78.0,
      level: "high",
      condition: "disruption",
      started_at: Time.utc(2026, 3, 25, 9, 0, 0),
      fetched_at: Time.utc(2026, 3, 25, 9, 5, 0)
    )

    event = OperationalOntologySyncService.sync_outage(outage)
    assert_equal ["Iran"], event.ontology_event_entities.includes(:ontology_entity).map { |row| row.ontology_entity.canonical_name }

    outage.update!(entity_code: "IQ", entity_name: "Iraq", updated_at: Time.current)
    event = OperationalOntologySyncService.sync_outage(outage)

    assert_equal 1, event.ontology_event_entities.where(role: "affected_party").count
    assert_equal ["Iraq"], event.ontology_event_entities.includes(:ontology_entity).map { |row| row.ontology_entity.canonical_name }
  end
end
