require "test_helper"

class Api::NodeContextsControllerTest < ActionDispatch::IntegrationTest
  test "returns durable relationships for a chokepoint node" do
    theater = OntologyEntity.create!(
      canonical_key: "theater:test-theater",
      entity_type: "theater",
      canonical_name: "Test Theater",
      metadata: { "cluster_count" => 4, "total_sources" => 11, "situation_names" => ["Hormuz", "Gulf States"] }
    )
    hormuz = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:hormuz",
      entity_type: "corridor",
      canonical_name: "Strait of Hormuz",
      metadata: { "description" => "Strategic energy corridor", "latitude" => 26.56, "longitude" => 56.27 }
    )
    cluster = create_story_cluster("cluster:hormuz", "Shipping pressure builds around Hormuz")

    relationship = OntologyRelationship.create!(
      source_node: theater,
      target_node: hormuz,
      relation_type: "theater_pressure",
      confidence: 0.93,
      fresh_until: 2.hours.from_now,
      derived_by: "test",
      explanation: "Test Theater is exerting pressure on Strait of Hormuz"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: cluster,
      evidence_role: "local_story",
      confidence: 0.84
    )

    get "/api/node_context", params: { kind: "chokepoint", id: "Strait of Hormuz" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Strait of Hormuz", body.dig("node", "name")
    assert_in_delta 26.56, body.dig("node", "latitude"), 0.001
    assert_in_delta 56.27, body.dig("node", "longitude"), 0.001
    assert_equal "Shipping pressure builds around Hormuz", body.dig("evidence", 0, "label")
    assert_equal "theater_pressure", body.dig("relationships", 0, "relation_type")
    assert_equal "Test Theater", body.dig("relationships", 0, "node", "name")
    assert_equal "local_story", body.dig("relationships", 0, "evidence", 0, "role")
  end

  test "returns theater node context by slug with durable evidence" do
    theater = OntologyEntity.create!(
      canonical_key: "theater:test-theater",
      entity_type: "theater",
      canonical_name: "Test Theater",
      metadata: { "cluster_count" => 4, "total_sources" => 11, "situation_names" => ["Hormuz", "Gulf States"] }
    )
    hormuz = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:hormuz",
      entity_type: "corridor",
      canonical_name: "Strait of Hormuz",
      metadata: { "description" => "Strategic energy corridor" }
    )
    cluster = create_story_cluster("cluster:hormuz", "Shipping pressure builds around Hormuz")

    relationship = OntologyRelationship.create!(
      source_node: theater,
      target_node: hormuz,
      relation_type: "theater_pressure",
      confidence: 0.93,
      fresh_until: 2.hours.from_now,
      derived_by: "test",
      explanation: "Test Theater is exerting pressure on Strait of Hormuz"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: cluster,
      evidence_role: "local_story",
      confidence: 0.84
    )

    get "/api/node_context", params: { kind: "theater", id: "test-theater" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Test Theater", body.dig("node", "name")
    assert_equal "4 clusters · 11 sources · Hormuz, Gulf States", body.dig("node", "summary")
    assert_equal "Shipping pressure builds around Hormuz", body.dig("evidence", 0, "label")
    assert_equal "theater_pressure", body.dig("relationships", 0, "relation_type")
    assert_equal "Strait of Hormuz", body.dig("relationships", 0, "node", "name")
  end

  test "returns memberships and evidence for a news story cluster node" do
    source = NewsSource.create!(canonical_key: "test-source", name: "Test Source", source_kind: "wire")
    article = NewsArticle.create!(
      news_source: source,
      url: "https://example.com/story",
      canonical_url: "https://example.com/story",
      normalization_status: "normalized",
      content_scope: "core",
      title: "Lead article"
    )
    cluster = create_story_cluster("cluster:story", "Story cluster title", lead_article: article)
    actor = OntologyEntity.create!(
      canonical_key: "actor:iran",
      entity_type: "actor",
      canonical_name: "Iran"
    )
    event = OntologyEvent.create!(
      canonical_key: "news-story-cluster:#{cluster.cluster_key}",
      event_family: cluster.event_family,
      event_type: cluster.event_type,
      status: "active",
      verification_status: cluster.verification_status,
      geo_precision: cluster.geo_precision,
      confidence: cluster.cluster_confidence,
      source_reliability: cluster.source_reliability,
      geo_confidence: cluster.geo_confidence,
      primary_story_cluster: cluster
    )
    OntologyEventEntity.create!(
      ontology_event: event,
      ontology_entity: actor,
      role: "participant",
      confidence: 0.88
    )
    OntologyEvidenceLink.create!(
      ontology_event: event,
      evidence: cluster,
      evidence_role: "primary_cluster",
      confidence: 0.84
    )
    OntologyEvidenceLink.create!(
      ontology_event: event,
      evidence: article,
      evidence_role: "lead_article",
      confidence: 0.82
    )

    get "/api/node_context", params: { kind: "news_story_cluster", id: cluster.cluster_key }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Story cluster title", body.dig("node", "name")
    assert_in_delta 26.7, body.dig("node", "latitude"), 0.001
    assert_in_delta 56.4, body.dig("node", "longitude"), 0.001
    assert_equal "participant", body.dig("memberships", 0, "role")
    assert_equal "Iran", body.dig("memberships", 0, "node", "name")
    assert_equal ["lead_article", "primary_cluster"], body.fetch("evidence").map { |item| item.fetch("role") }.sort
  end

  test "returns commodity node context by symbol" do
    hormuz = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:hormuz",
      entity_type: "corridor",
      canonical_name: "Strait of Hormuz",
      metadata: { "description" => "Strategic energy corridor" }
    )
    brent = OntologyEntity.create!(
      canonical_key: "commodity:oil_brent",
      entity_type: "commodity",
      canonical_name: "Brent Crude",
      metadata: { "symbol" => "OIL_BRENT", "latest_price" => 84.2, "change_pct" => 1.8, "unit" => "USD", "region" => "Global" }
    )
    OntologyEntityAlias.create!(ontology_entity: brent, name: "OIL_BRENT", alias_type: "ticker")
    price = CommodityPrice.create!(
      symbol: "OIL_BRENT",
      category: "commodity",
      name: "Brent Crude",
      price: 84.2,
      change_pct: 1.8,
      unit: "USD",
      recorded_at: Time.current
    )

    relationship = OntologyRelationship.create!(
      source_node: hormuz,
      target_node: brent,
      relation_type: "flow_dependency",
      confidence: 0.88,
      fresh_until: 2.hours.from_now,
      derived_by: "test",
      explanation: "Hormuz carries major Brent exposure"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: price,
      evidence_role: "market_signal",
      confidence: 0.76
    )

    get "/api/node_context", params: { kind: "commodity", id: "OIL_BRENT" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Brent Crude", body.dig("node", "name")
    assert_equal "OIL_BRENT · 84.2 USD · +1.8% · Global", body.dig("node", "summary")
    assert_equal "Brent Crude", body.dig("evidence", 0, "label")
    assert_equal "flow_dependency", body.dig("relationships", 0, "relation_type")
    assert_equal "Strait of Hormuz", body.dig("relationships", 0, "node", "name")
  end

  test "returns generic entity node context by canonical key" do
    chokepoint = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:hormuz",
      entity_type: "corridor",
      canonical_name: "Strait of Hormuz",
      metadata: { "description" => "Strategic energy corridor" }
    )
    airport = OntologyEntity.create!(
      canonical_key: "airport:ooms",
      entity_type: "airport",
      canonical_name: "Khasab Airport",
      country_code: "OM",
      metadata: { "airport_type" => "large_airport", "municipality" => "Khasab" }
    )

    relationship = OntologyRelationship.create!(
      source_node: chokepoint,
      target_node: airport,
      relation_type: "downstream_exposure",
      confidence: 0.81,
      fresh_until: 2.hours.from_now,
      derived_by: "test",
      explanation: "Khasab Airport lies close to Strait of Hormuz"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: NewsStoryCluster.create!(
        cluster_key: "cluster:airport",
        canonical_title: "Hormuz shipping disruption risk",
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
      ),
      evidence_role: "supporting_story",
      confidence: 0.74
    )

    get "/api/node_context", params: { kind: "entity", id: "airport:ooms" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Khasab Airport", body.dig("node", "name")
    assert_equal "large_airport · OM · Khasab", body.dig("node", "summary")
    assert_equal "downstream_exposure", body.dig("relationships", 0, "relation_type")
    assert_equal "Strait of Hormuz", body.dig("relationships", 0, "node", "name")
  end

  test "returns asset entity context with operational activity evidence" do
    theater = OntologyEntity.create!(
      canonical_key: "theater:middle-east-iran-war",
      entity_type: "theater",
      canonical_name: "Middle East / Iran War",
      metadata: { "cluster_count" => 6, "total_sources" => 22, "situation_names" => ["Hormuz"] }
    )
    flight_entity = OntologyEntity.create!(
      canonical_key: "asset:flight:icao24:abc123",
      entity_type: "asset",
      canonical_name: "RCH432",
      metadata: {
        "asset_kind" => "flight",
        "military" => true,
        "origin_country" => "United States",
        "aircraft_type" => "C17",
      }
    )
    flight = Flight.create!(
      icao24: "abc123",
      callsign: "RCH432",
      latitude: 26.2,
      longitude: 56.3,
      source: "adsb",
      origin_country: "United States",
      aircraft_type: "C17",
      military: true
    )

    relationship = OntologyRelationship.create!(
      source_node: flight_entity,
      target_node: theater,
      relation_type: "operational_activity",
      confidence: 0.91,
      fresh_until: 2.hours.from_now,
      derived_by: "test",
      explanation: "RCH432 is operating near Middle East / Iran War activity"
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: flight,
      evidence_role: "tracked_asset",
      confidence: 0.84
    )

    get "/api/node_context", params: { kind: "entity", id: "asset:flight:icao24:abc123" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "RCH432", body.dig("node", "name")
    assert_equal "flight · military · United States · C17", body.dig("node", "summary")
    assert_equal "flight", body.dig("evidence", 0, "type")
    assert_equal "Middle East / Iran War", body.dig("relationships", 0, "node", "name")
    assert_equal "operational_activity", body.dig("relationships", 0, "relation_type")
  end

  test "returns country entity context with supply-chain evidence labels" do
    japan = OntologyEntity.create!(
      canonical_key: "country:jpn",
      entity_type: "country",
      canonical_name: "Japan",
      country_code: "JP",
      metadata: {
        "gdp_nominal_usd" => 4_200_000_000_000,
        "imports_goods_services_pct_gdp" => 21.6,
        "energy_imports_net_pct_energy_use" => 87.4,
        "latest_year" => 2024,
      }
    )
    crude_oil = OntologyEntity.create!(
      canonical_key: "commodity:oil_crude",
      entity_type: "commodity",
      canonical_name: "Crude Oil",
      metadata: { "description" => "Strategic supply-chain commodity" }
    )
    dependency = CountryCommodityDependency.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      supplier_count: 2,
      top_partner_country_code: "AE",
      top_partner_country_code_alpha3: "ARE",
      top_partner_country_name: "United Arab Emirates",
      top_partner_share_pct: 75.0,
      import_share_gdp_pct: 0.0476,
      dependency_score: 0.64,
      metadata: {},
      fetched_at: Time.current
    )

    relationship = OntologyRelationship.create!(
      source_node: crude_oil,
      target_node: japan,
      relation_type: "import_dependency",
      confidence: 0.78,
      derived_by: "test",
      explanation: "Japan depends on imported crude oil."
    )
    OntologyRelationshipEvidence.create!(
      ontology_relationship: relationship,
      evidence: dependency,
      evidence_role: "dependency_profile",
      confidence: 0.74
    )

    get "/api/node_context", params: { kind: "entity", id: "country:jpn" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Japan", body.dig("node", "name")
    assert_equal "GDP $4.2T · 21.6% imports/GDP · 87.4% net energy imports · 2024", body.dig("node", "summary")
    assert_equal "Japan crude oil imports", body.dig("evidence", 0, "label")
    assert_equal "dependency_profile", body.dig("evidence", 0, "role")
    assert_equal "import_dependency", body.dig("relationships", 0, "relation_type")
    assert_equal "Crude Oil", body.dig("relationships", 0, "node", "name")
  end

  private

  def create_story_cluster(key, title, lead_article: nil)
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
      geo_confidence: 0.82,
      lead_news_article: lead_article
    )
  end
end
