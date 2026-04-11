require "test_helper"

class OntologyRelationshipSyncServiceTest < ActiveSupport::TestCase
  test "builds Hormuz theater pressure and flow dependency relationships with evidence" do
    travel_to Time.utc(2026, 3, 25, 16, 0, 0) do
      tehran_cluster = create_conflict_cluster(
        key: "cluster:iran-theater",
        title: "Iran war escalates around Tehran",
        latitude: 35.69,
        longitude: 51.39,
        source_count: 10,
        last_seen_at: 20.minutes.ago
      )
      hormuz_cluster = create_conflict_cluster(
        key: "cluster:hormuz-shipping",
        title: "All eyes on Strait of Hormuz as Iran threatens shipping",
        latitude: 26.72,
        longitude: 56.42,
        source_count: 4,
        last_seen_at: 10.minutes.ago
      )
      brent = create_commodity(symbol: "OIL_BRENT", name: "Brent Crude", price: 84.20, change_pct: 1.8)
      wti = create_commodity(symbol: "OIL_WTI", name: "WTI Crude", price: 79.10, change_pct: 1.4)
      lng = create_commodity(symbol: "LNG", name: "Liquefied Natural Gas", price: 12.50, change_pct: 2.2)

      result = OntologyRelationshipSyncService.sync_recent

      assert_operator result[:theater_pressure], :>=, 3
      assert_operator result[:flow_dependencies], :>=, 3
      assert_equal "Strait of Hormuz", ChokepointMonitorService::CHOKEPOINTS[:hormuz][:name]

      theater = OntologyEntity.find_by!(canonical_key: "theater:middle-east-iran-war")
      hormuz = OntologyEntity.find_by!(canonical_key: "corridor:chokepoint:hormuz")
      pressure = OntologyRelationship.find_by!(
        source_node: theater,
        target_node: hormuz,
        relation_type: "theater_pressure"
      )

      assert pressure.active?
      assert_operator pressure.confidence, :>=, 0.7
      assert_includes pressure.explanation, "Middle East / Iran War"
      assert_includes pressure.explanation, "Strait of Hormuz"

      evidence_roles = pressure.ontology_relationship_evidences.includes(:evidence).map { |row| [row.evidence, row.evidence_role] }
      assert_includes evidence_roles, [hormuz_cluster, "local_story"]
      assert_includes evidence_roles, [tehran_cluster, "supporting_story"]

      {
        "commodity:oil_brent" => brent,
        "commodity:oil_wti" => wti,
        "commodity:lng" => lng,
      }.each do |canonical_key, price|
        commodity = OntologyEntity.find_by!(canonical_key: canonical_key)
        relation = OntologyRelationship.find_by!(
          source_node: hormuz,
          target_node: commodity,
          relation_type: "flow_dependency"
        )

        assert relation.active?
        assert_equal price, relation.ontology_relationship_evidences.find_by!(evidence_role: "market_reference").evidence
      end
    end
  end

  test "pulls corroborated chokepoint shipping stories into local theater evidence" do
    travel_to Time.utc(2026, 3, 25, 16, 0, 0) do
      create_conflict_cluster(
        key: "cluster:iran-theater",
        title: "Iran war escalates around Tehran",
        latitude: 35.69,
        longitude: 51.39,
        source_count: 10,
        last_seen_at: 20.minutes.ago
      )
      local_shipping_cluster = create_story_cluster(
        key: "cluster:hormuz-shipping-local",
        title: "UAE joins allies demanding Iran halt Strait of Hormuz shipping attacks",
        family: "diplomacy",
        event_type: "diplomatic_contact",
        latitude: 24.45,
        longitude: 54.65,
        source_count: 3,
        last_seen_at: 10.minutes.ago
      )

      OntologyRelationshipSyncService.sync_recent

      theater = OntologyEntity.find_by!(canonical_key: "theater:middle-east-iran-war")
      hormuz = OntologyEntity.find_by!(canonical_key: "corridor:chokepoint:hormuz")
      pressure = OntologyRelationship.find_by!(
        source_node: theater,
        target_node: hormuz,
        relation_type: "theater_pressure"
      )

      assert_includes pressure.explanation, "directly about the chokepoint"
      assert_includes pressure.ontology_relationship_evidences.map(&:evidence), local_shipping_cluster
      assert pressure.ontology_relationship_evidences.exists?(evidence: local_shipping_cluster, evidence_role: "local_story")
    end
  end

  test "maps Russia-Ukraine theater pressure to Bosphorus without local chokepoint overlap" do
    travel_to Time.utc(2026, 3, 25, 16, 0, 0) do
      create_conflict_cluster(
        key: "cluster:ukraine-front",
        title: "Ukraine war escalation threatens Black Sea shipping",
        latitude: 50.45,
        longitude: 30.52,
        source_count: 6,
        last_seen_at: 30.minutes.ago
      )

      OntologyRelationshipSyncService.sync_recent

      theater = OntologyEntity.find_by!(canonical_key: "theater:russia-ukraine-war")
      bosphorus = OntologyEntity.find_by!(canonical_key: "corridor:chokepoint:bosphorus")
      relation = OntologyRelationship.find_by!(
        source_node: theater,
        target_node: bosphorus,
        relation_type: "theater_pressure"
      )

      assert relation.active?
      assert_equal ["supporting_story"], relation.ontology_relationship_evidences.pluck(:evidence_role).uniq
      assert_includes relation.explanation, "Russia-Ukraine War"
      assert_includes relation.explanation, "Bosphorus Strait"
    end
  end

  test "builds downstream exposure from pressured corridors and theaters to strategic assets" do
    travel_to Time.utc(2026, 3, 25, 16, 0, 0) do
      supporting_cluster = create_conflict_cluster(
        key: "cluster:iran-theater",
        title: "Iran war escalates around Tehran",
        latitude: 35.69,
        longitude: 51.39,
        source_count: 9,
        last_seen_at: 30.minutes.ago
      )
      create_conflict_cluster(
        key: "cluster:hormuz-shipping",
        title: "Shipping pressure rises in the Strait of Hormuz",
        latitude: 26.65,
        longitude: 56.35,
        source_count: 4,
        last_seen_at: 10.minutes.ago
      )

      airport = Airport.create!(
        icao_code: "OOMS",
        iata_code: "KHS",
        name: "Khasab Airport",
        airport_type: "large_airport",
        latitude: 26.17,
        longitude: 56.24,
        country_code: "OM",
        municipality: "Khasab",
        is_military: false
      )
      base = MilitaryBase.create!(
        external_id: "base-hormuz-1",
        name: "Hormuz Coastal Base",
        base_type: "navy",
        country: "Oman",
        operator: "Royal Navy of Oman",
        latitude: 26.58,
        longitude: 56.31,
        source: "test"
      )
      plant = PowerPlant.create!(
        gppd_idnr: "OM001",
        name: "Hormuz Gas Plant",
        country_code: "OM",
        country_name: "Oman",
        latitude: 26.32,
        longitude: 56.38,
        capacity_mw: 520,
        primary_fuel: "Gas"
      )
      cable = SubmarineCable.create!(
        cable_id: "gulf-cable-1",
        name: "Gulf Data Link",
        landing_points: [{ "lat" => 26.56, "lng" => 56.29 }]
      )

      result = OntologyRelationshipSyncService.sync_recent

      assert_operator result[:downstream_exposures], :>=, 6

      theater = OntologyEntity.find_by!(canonical_key: "theater:middle-east-iran-war")
      hormuz = OntologyEntity.find_by!(canonical_key: "corridor:chokepoint:hormuz")
      airport_entity = OntologyEntity.find_by!(canonical_key: "airport:ooms")
      base_entity = OntologyEntity.find_by!(canonical_key: "military-base:base-hormuz-1")
      plant_entity = OntologyEntity.find_by!(canonical_key: "power-plant:om001")
      cable_entity = OntologyEntity.find_by!(canonical_key: "submarine-cable:gulf-cable-1")

      [airport_entity, base_entity, plant_entity, cable_entity].each do |asset_entity|
        chokepoint_relation = OntologyRelationship.find_by!(
          source_node: hormuz,
          target_node: asset_entity,
          relation_type: "downstream_exposure"
        )
        assert chokepoint_relation.active?
        assert_equal "exposed_asset", chokepoint_relation.ontology_relationship_evidences.first.evidence_role

        theater_relation = OntologyRelationship.find_by!(
          source_node: theater,
          target_node: asset_entity,
          relation_type: "downstream_exposure"
        )
        assert theater_relation.active?
        assert_includes theater_relation.ontology_relationship_evidences.map(&:evidence), supporting_cluster
      end

      assert_includes OntologyRelationship.find_by!(source_node: hormuz, target_node: airport_entity, relation_type: "downstream_exposure").explanation, airport.name
      assert_includes OntologyRelationship.find_by!(source_node: theater, target_node: cable_entity, relation_type: "downstream_exposure").explanation, "Strait of Hormuz"
    end
  end

  test "builds operational activity relationships for ships, flights, theaters, assets, and cables" do
    travel_to Time.utc(2026, 3, 25, 16, 0, 0) do
      create_conflict_cluster(
        key: "cluster:iran-theater",
        title: "Iran war escalates around Tehran",
        latitude: 35.69,
        longitude: 51.39,
        source_count: 9,
        last_seen_at: 35.minutes.ago
      )
      supporting_cluster = create_conflict_cluster(
        key: "cluster:hormuz-shipping",
        title: "Shipping pressure rises in the Strait of Hormuz",
        latitude: 26.65,
        longitude: 56.35,
        source_count: 4,
        last_seen_at: 10.minutes.ago
      )

      airport = Airport.create!(
        icao_code: "OOMS",
        iata_code: "KHS",
        name: "Khasab Airport",
        airport_type: "large_airport",
        latitude: 26.17,
        longitude: 56.24,
        country_code: "OM",
        municipality: "Khasab",
        is_military: false
      )
      MilitaryBase.create!(
        external_id: "base-hormuz-1",
        name: "Hormuz Coastal Base",
        base_type: "navy",
        country: "Oman",
        operator: "Royal Navy of Oman",
        latitude: 26.58,
        longitude: 56.31,
        source: "test"
      )
      cable = SubmarineCable.create!(
        cable_id: "gulf-cable-1",
        name: "Gulf Data Link",
        landing_points: [{ "lat" => 26.56, "lng" => 56.29 }]
      )

      ship = Ship.create!(
        mmsi: "123456789",
        name: "Mercury Trader",
        ship_type: 70,
        latitude: 26.61,
        longitude: 56.30,
        speed: 0.6,
        heading: 91.0,
        destination: "Muscat",
        flag: "OM",
        updated_at: 10.minutes.ago
      )
      flight = Flight.create!(
        icao24: "abc123",
        callsign: "RCH432",
        latitude: 26.24,
        longitude: 56.33,
        speed: 420,
        heading: 120.0,
        origin_country: "United States",
        source: "adsb",
        aircraft_type: "C17",
        military: true,
        updated_at: 8.minutes.ago
      )
      GpsJammingSnapshot.create!(
        cell_lat: 26.20,
        cell_lng: 56.40,
        total: 20,
        bad: 8,
        percentage: 40.0,
        level: "high",
        recorded_at: 15.minutes.ago
      )
      Notam.create!(
        external_id: "NOTAM-HORMUZ-1",
        source: "test",
        latitude: 26.25,
        longitude: 56.31,
        radius_nm: 40.0,
        reason: "Military",
        text: "Military activity",
        country: "OM",
        effective_start: 2.hours.ago,
        effective_end: 8.hours.from_now,
        fetched_at: 30.minutes.ago
      )

      result = OntologyRelationshipSyncService.sync_recent

      assert_operator result[:operational_activities], :>=, 4

      ship_entity = OntologyEntity.find_by!(canonical_key: "asset:ship:mmsi:123456789")
      flight_entity = OntologyEntity.find_by!(canonical_key: "asset:flight:icao24:abc123")
      hormuz = OntologyEntity.find_by!(canonical_key: "corridor:chokepoint:hormuz")
      theater = OntologyEntity.find_by!(canonical_key: "theater:middle-east-iran-war")
      airport_entity = OntologyEntity.find_by!(canonical_key: "airport:ooms")
      cable_entity = OntologyEntity.find_by!(canonical_key: "submarine-cable:gulf-cable-1")

      chokepoint_relation = OntologyRelationship.find_by!(
        source_node: ship_entity,
        target_node: hormuz,
        relation_type: "operational_activity"
      )
      assert chokepoint_relation.active?
      assert_includes chokepoint_relation.explanation, "Strait of Hormuz"
      assert_includes chokepoint_relation.ontology_relationship_evidences.map(&:evidence), ship
      assert_includes chokepoint_relation.ontology_relationship_evidences.map(&:evidence), supporting_cluster

      cable_relation = OntologyRelationship.find_by!(
        source_node: ship_entity,
        target_node: cable_entity,
        relation_type: "operational_activity"
      )
      assert cable_relation.active?
      assert_includes cable_relation.explanation, cable.name
      assert_equal ["tracked_asset"], cable_relation.ontology_relationship_evidences.pluck(:evidence_role).uniq

      theater_relation = OntologyRelationship.find_by!(
        source_node: flight_entity,
        target_node: theater,
        relation_type: "operational_activity"
      )
      assert theater_relation.active?
      assert_includes theater_relation.explanation, "Middle East / Iran War"
      assert_includes theater_relation.ontology_relationship_evidences.pluck(:evidence_role), "tracked_asset"
      assert_includes theater_relation.ontology_relationship_evidences.pluck(:evidence_role), "jamming_signal"
      assert_includes theater_relation.ontology_relationship_evidences.pluck(:evidence_role), "airspace_notice"

      airport_relation = OntologyRelationship.find_by!(
        source_node: flight_entity,
        target_node: airport_entity,
        relation_type: "operational_activity"
      )
      assert airport_relation.active?
      assert_includes airport_relation.explanation, airport.name
      assert_includes airport_relation.metadata.fetch("theaters"), "Middle East / Iran War"
    end
  end

  test "keeps recent operational activity relationships when live feeds are stale" do
    travel_to Time.utc(2026, 3, 26, 10, 0, 0) do
      create_conflict_cluster(
        key: "cluster:iran-theater",
        title: "Iran war escalates around Tehran",
        latitude: 35.69,
        longitude: 51.39,
        source_count: 8,
        last_seen_at: 30.minutes.ago
      )
      create_conflict_cluster(
        key: "cluster:hormuz-shipping",
        title: "Shipping pressure rises in the Strait of Hormuz",
        latitude: 26.65,
        longitude: 56.35,
        source_count: 3,
        last_seen_at: 15.minutes.ago
      )

      Ship.create!(
        mmsi: "987654321",
        name: "Delayed Tanker",
        ship_type: 80,
        latitude: 26.58,
        longitude: 56.28,
        speed: 1.8,
        destination: "Fujairah",
        flag: "PA",
        updated_at: 4.hours.ago
      )
      Flight.create!(
        icao24: "def456",
        callsign: "RRR901",
        latitude: 26.30,
        longitude: 56.30,
        speed: 410,
        heading: 118.0,
        origin_country: "United Kingdom",
        source: "adsb",
        aircraft_type: "A400M",
        military: true,
        updated_at: 5.hours.ago
      )

      result = OntologyRelationshipSyncService.sync_recent

      assert_operator result[:operational_activities], :>=, 2

      ship_entity = OntologyEntity.find_by!(canonical_key: "asset:ship:mmsi:987654321")
      flight_entity = OntologyEntity.find_by!(canonical_key: "asset:flight:icao24:def456")
      hormuz = OntologyEntity.find_by!(canonical_key: "corridor:chokepoint:hormuz")
      theater = OntologyEntity.find_by!(canonical_key: "theater:middle-east-iran-war")

      ship_relation = OntologyRelationship.find_by!(
        source_node: ship_entity,
        target_node: hormuz,
        relation_type: "operational_activity"
      )
      assert_equal "recent", ship_relation.metadata.fetch("freshness_tier")
      assert_includes ship_relation.explanation, "recently operated"

      flight_relation = OntologyRelationship.find_by!(
        source_node: flight_entity,
        target_node: theater,
        relation_type: "operational_activity"
      )
      assert_equal "recent", flight_relation.metadata.fetch("freshness_tier")
      assert_equal "recent", flight_relation.ontology_relationship_evidences.find_by!(evidence_role: "tracked_asset").metadata.fetch("freshness_tier")
    end
  end

  test "builds local corroboration between weather story events and nearby cameras" do
    travel_to Time.utc(2026, 3, 26, 10, 0, 0) do
      cluster = create_story_cluster(
        key: "cluster:sharjah-flood",
        title: "Flooded streets in Sharjah after heavy rain hits the United Arab Emirates",
        family: "weather",
        event_type: "flood",
        latitude: 25.35,
        longitude: 55.39,
        source_count: 4,
        last_seen_at: 25.minutes.ago
      )
      event = NewsOntologySyncService.sync_story_cluster(cluster)
      camera = Camera.create!(
        webcam_id: "windy-sharjah-1",
        source: "windy",
        title: "Sharjah Corniche Cam",
        latitude: 25.37,
        longitude: 55.40,
        city: "Sharjah",
        country: "AE",
        fetched_at: 20.minutes.ago,
        expires_at: 2.days.from_now,
        is_live: true
      )

      result = OntologyRelationshipSyncService.sync_recent

      assert_operator result[:local_corroborations], :>=, 1

      camera_entity = OntologyEntity.find_by!(canonical_key: "asset:camera:windy:windy-sharjah-1")
      relation = OntologyRelationship.find_by!(
        source_node: event,
        target_node: camera_entity,
        relation_type: "local_corroboration"
      )

      assert relation.active?
      assert_equal "camera", relation.metadata.fetch("target_kind")
      assert_includes relation.explanation, camera.title
      assert_includes relation.ontology_relationship_evidences.map(&:evidence), camera
      assert_includes relation.ontology_relationship_evidences.map(&:evidence), cluster
    end
  end

  test "builds infrastructure exposure relationships from hazards to nearby strategic assets" do
    travel_to Time.utc(2026, 4, 11, 12, 0, 0) do
      earthquake = Earthquake.create!(
        external_id: "eq-hormuz-1",
        title: "M6.4 earthquake near the Strait of Hormuz",
        magnitude: 6.4,
        magnitude_type: "mww",
        latitude: 26.32,
        longitude: 56.25,
        depth: 12.0,
        event_time: 20.minutes.ago,
        tsunami: false,
        alert: "yellow",
        fetched_at: Time.current
      )
      Airport.create!(
        icao_code: "OOTH",
        iata_code: "THM",
        name: "Test Hormuz Airport",
        airport_type: "large_airport",
        latitude: 26.36,
        longitude: 56.28,
        country_code: "OM",
        municipality: "Test City",
        is_military: false
      )
      MilitaryBase.create!(
        external_id: "base-hormuz-hazard-1",
        name: "Hormuz Hazard Base",
        base_type: "navy",
        country: "Oman",
        operator: "Test Navy",
        latitude: 26.40,
        longitude: 56.30,
        source: "test"
      )
      plant = PowerPlant.create!(
        gppd_idnr: "OM-HORMUZ-HAZARD-1",
        name: "Hormuz Hazard Gas Plant",
        country_code: "OM",
        country_name: "Oman",
        latitude: 26.38,
        longitude: 56.32,
        capacity_mw: 640,
        primary_fuel: "Gas"
      )

      result = OntologyRelationshipSyncService.sync_recent

      assert_operator result[:infrastructure_disruptions], :>=, 3

      event = OntologyEvent.find_by!(canonical_key: "event:earthquake:eq-hormuz-1")
      plant_entity = OntologyEntity.find_by!(canonical_key: "power-plant:om-hormuz-hazard-1")
      relation = OntologyRelationship.find_by!(
        source_node: event,
        target_node: plant_entity,
        relation_type: "infrastructure_exposure"
      )

      assert relation.active?
      assert_equal "disaster", event.event_family
      assert_equal "earthquake", relation.metadata.fetch("event_kind")
      assert_includes relation.explanation, plant.name

      evidence_roles = relation.ontology_relationship_evidences.includes(:evidence).map { |row| [row.evidence, row.evidence_role] }
      assert_includes evidence_roles, [earthquake, "hazard_observation"]
      assert_includes evidence_roles, [plant, "exposed_asset"]
    end
  end

  test "links thermal strike signals to ports as disruptions and submarine cables as exposure" do
    travel_to Time.utc(2026, 4, 11, 12, 0, 0) do
      strike = FireHotspot.create!(
        external_id: "firms-strike-port-1",
        latitude: 29.08,
        longitude: 50.82,
        brightness: 372.0,
        confidence: "high",
        satellite: "Suomi NPP",
        instrument: "VIIRS",
        frp: 48.0,
        daynight: "N",
        acq_datetime: 15.minutes.ago,
        fetched_at: Time.current
      )
      port = TradeLocation.create!(
        locode: "IRBND",
        country_code: "IR",
        country_code_alpha3: "IRN",
        country_name: "Iran",
        name: "Bandar Test Port",
        normalized_name: "bandar test port",
        location_kind: "port",
        function_codes: "1",
        latitude: 29.081,
        longitude: 50.821,
        status: "active",
        source: "test_feed",
        fetched_at: Time.current,
        metadata: { "harbor_size" => "large", "flow_types" => %w[oil trade] }
      )
      cable = SubmarineCable.create!(
        cable_id: "gulf-cable-exposure-1",
        name: "Gulf Cable Exposure",
        landing_points: [{ "lat" => 29.082, "lng" => 50.822, "country_code" => "IR" }]
      )

      result = OntologyRelationshipSyncService.sync_recent

      assert_operator result[:infrastructure_disruptions], :>=, 2

      event = OntologyEvent.find_by!(canonical_key: "event:thermal-strike:firms-strike-port-1")
      port_entity = OntologyEntity.find_by!(canonical_key: "port:irbnd")
      cable_entity = OntologyEntity.find_by!(canonical_key: "submarine-cable:gulf-cable-exposure-1")

      port_relation = OntologyRelationship.find_by!(
        source_node: event,
        target_node: port_entity,
        relation_type: "infrastructure_disruption"
      )
      cable_relation = OntologyRelationship.find_by!(
        source_node: event,
        target_node: cable_entity,
        relation_type: "infrastructure_exposure"
      )

      assert port_relation.active?
      assert cable_relation.active?
      assert_equal "thermal_strike", event.event_type
      assert_equal "port", port_relation.metadata.fetch("asset_type")
      assert_equal "submarine_cable", cable_relation.metadata.fetch("asset_type")
      assert_includes port_relation.explanation, port.name
      assert_includes cable_relation.explanation, cable.name
      assert_includes port_relation.ontology_relationship_evidences.map(&:evidence), strike
    end
  end

  test "promotes submarine cable exposure to disruption when matching outage evidence exists" do
    travel_to Time.utc(2026, 4, 11, 12, 0, 0) do
      earthquake = Earthquake.create!(
        external_id: "eq-cable-outage-1",
        title: "M6.5 earthquake near Gulf cable landing",
        magnitude: 6.5,
        latitude: 29.08,
        longitude: 50.82,
        depth: 10.0,
        event_time: 20.minutes.ago,
        tsunami: false,
        alert: "yellow",
        fetched_at: Time.current
      )
      cable = SubmarineCable.create!(
        cable_id: "gulf-cable-outage-1",
        name: "Gulf Cable Outage",
        landing_points: [{ "lat" => 29.081, "lng" => 50.821, "country_code" => "IR" }]
      )
      outage = InternetOutage.create!(
        external_id: "IR-ioda-test-1",
        entity_type: "country",
        entity_code: "IR",
        entity_name: "Iran",
        datasource: "ioda",
        score: 12_000,
        level: "severe",
        condition: "outage",
        started_at: 10.minutes.ago,
        fetched_at: Time.current
      )

      OntologyRelationshipSyncService.sync_recent

      event = OntologyEvent.find_by!(canonical_key: "event:earthquake:eq-cable-outage-1")
      cable_entity = OntologyEntity.find_by!(canonical_key: "submarine-cable:gulf-cable-outage-1")
      relation = OntologyRelationship.find_by!(
        source_node: event,
        target_node: cable_entity,
        relation_type: "infrastructure_disruption"
      )

      assert relation.active?
      assert_includes relation.explanation, cable.name
      assert_includes relation.ontology_relationship_evidences.map(&:evidence), earthquake
      assert_includes relation.ontology_relationship_evidences.map(&:evidence), outage
      assert_includes relation.ontology_relationship_evidences.pluck(:evidence_role), "supporting_outage"
    end
  end

  private

  def create_conflict_cluster(key:, title:, latitude:, longitude:, source_count:, last_seen_at:)
    create_story_cluster(
      key: key,
      title: title,
      family: "conflict",
      event_type: "military_activity",
      latitude: latitude,
      longitude: longitude,
      source_count: source_count,
      last_seen_at: last_seen_at
    )
  end

  def create_story_cluster(key:, title:, family:, event_type:, latitude:, longitude:, source_count:, last_seen_at:)
    NewsStoryCluster.create!(
      cluster_key: key,
      canonical_title: title,
      content_scope: "core",
      event_family: family,
      event_type: event_type,
      location_name: title,
      latitude: latitude,
      longitude: longitude,
      geo_precision: "point",
      first_seen_at: last_seen_at - 30.minutes,
      last_seen_at: last_seen_at,
      article_count: source_count,
      source_count: source_count,
      cluster_confidence: 0.84,
      verification_status: "multi_source",
      source_reliability: 0.78,
      geo_confidence: 0.82
    )
  end

  def create_commodity(symbol:, name:, price:, change_pct:)
    CommodityPrice.create!(
      symbol: symbol,
      category: "commodity",
      name: name,
      price: price,
      change_pct: change_pct,
      recorded_at: Time.current
    )
  end
end
