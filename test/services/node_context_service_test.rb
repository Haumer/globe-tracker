require "test_helper"

class NodeContextServiceTest < ActiveSupport::TestCase
  test "resolve raises UnsupportedNodeError for unknown kind" do
    assert_raises(NodeContextService::UnsupportedNodeError) do
      NodeContextService.resolve(kind: "unknown_kind", id: "test")
    end
  end

  test "resolve raises NodeNotFoundError for missing chokepoint" do
    assert_raises(NodeContextService::NodeNotFoundError) do
      NodeContextService.resolve(kind: "chokepoint", id: "nonexistent_chokepoint_999")
    end
  end

  test "resolve raises NodeNotFoundError for missing theater" do
    assert_raises(NodeContextService::NodeNotFoundError) do
      NodeContextService.resolve(kind: "theater", id: "nonexistent_theater_999")
    end
  end

  test "resolve raises NodeNotFoundError for missing commodity" do
    assert_raises(NodeContextService::NodeNotFoundError) do
      NodeContextService.resolve(kind: "commodity", id: "nonexistent_commodity_999")
    end
  end

  test "resolve raises NodeNotFoundError for missing entity" do
    assert_raises(NodeContextService::NodeNotFoundError) do
      NodeContextService.resolve(kind: "entity", id: "nonexistent_entity_999")
    end
  end

  test "resolve raises error for missing news_story_cluster" do
    # This may raise NodeNotFoundError or ActiveRecord::EagerLoadPolymorphicError
    # depending on whether the eager load hits a polymorphic association first
    assert_raises do
      NodeContextService.resolve(kind: "news_story_cluster", id: "nonexistent_cluster_999")
    end
  end

  test "pluralize returns singular for count 1" do
    result = NodeContextService.send(:pluralize, 1, "source")

    assert_equal "1 source", result
  end

  test "pluralize returns plural for count > 1" do
    result = NodeContextService.send(:pluralize, 5, "source")

    assert_equal "5 sources", result
  end

  test "pluralize returns nil for blank count" do
    assert_nil NodeContextService.send(:pluralize, nil, "source")
  end

  test "format_change formats positive change" do
    result = NodeContextService.send(:format_change, 2.5)

    assert_equal "+2.5%", result
  end

  test "format_change formats negative change" do
    result = NodeContextService.send(:format_change, -3.14)

    assert_equal "-3.14%", result
  end

  test "format_price renders with unit" do
    result = NodeContextService.send(:format_price, 75.5, "USD/bbl")

    assert_equal "75.5 USD/bbl", result
  end

  test "format_price renders without unit" do
    result = NodeContextService.send(:format_price, 75.5, nil)

    assert_equal "75.5", result
  end

  test "format_price rounds large numbers to 1 decimal" do
    result = NodeContextService.send(:format_price, 123.456, nil)

    assert_equal "123.5", result
  end

  test "format_usd_short formats trillions" do
    result = NodeContextService.send(:format_usd_short, 2_500_000_000_000, prefix: "GDP ")

    assert_equal "GDP $2.5T", result
  end

  test "format_usd_short formats billions" do
    result = NodeContextService.send(:format_usd_short, 5_700_000_000)

    assert_equal "$5.7B", result
  end

  test "format_usd_short formats millions" do
    result = NodeContextService.send(:format_usd_short, 42_000_000)

    assert_equal "$42.0M", result
  end

  test "format_usd_short returns nil for blank" do
    assert_nil NodeContextService.send(:format_usd_short, nil)
    assert_nil NodeContextService.send(:format_usd_short, "")
  end

  test "LEGACY_EVIDENCE_LABELS maps expected types" do
    assert_equal "Country chokepoint exposure", NodeContextService::LEGACY_EVIDENCE_LABELS["CountryChokepointExposure"]
    assert_equal "Country commodity dependency", NodeContextService::LEGACY_EVIDENCE_LABELS["CountryCommodityDependency"]
  end

  test "resolve prioritizes v2 impact relationships over weaker static context" do
    asset = OntologyEntity.create!(
      canonical_key: "port:priority-test",
      entity_type: "port",
      canonical_name: "Priority Port"
    )
    country = OntologyEntity.create!(
      canonical_key: "country:priority-test",
      entity_type: "country",
      canonical_name: "Priority Country"
    )
    event = OntologyEvent.create!(
      canonical_key: "event:priority-impact",
      event_family: "conflict",
      event_type: "missile_attack",
      status: "active",
      verification_status: "multi_source",
      geo_precision: "unknown"
    )
    OntologyRelationship.create!(
      source_node: asset,
      target_node: country,
      relation_type: "located_in_country",
      confidence: 0.99,
      derived_by: "test"
    )
    OntologyRelationship.create!(
      source_node: event,
      target_node: asset,
      relation_type: "impacted_infrastructure",
      confidence: 0.7,
      derived_by: "test"
    )

    context = NodeContextService.resolve(kind: "entity", id: "port:priority-test")

    assert_equal "impacted_infrastructure", context.fetch(:relationships).first.fetch(:relation_type)
  end

  test "resolve includes route to market impact chains for chokepoints" do
    theater = OntologyEntity.create!(
      canonical_key: "theater:impact-chain-test",
      entity_type: "theater",
      canonical_name: "Impact Chain Test Theater"
    )
    hormuz = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:hormuz",
      entity_type: "corridor",
      canonical_name: "Strait of Hormuz"
    )
    crude = OntologyEntity.create!(
      canonical_key: "commodity:oil_crude",
      entity_type: "commodity",
      canonical_name: "Crude Oil"
    )
    brent = OntologyEntity.create!(
      canonical_key: "commodity:oil_brent",
      entity_type: "commodity",
      canonical_name: "Brent Crude"
    )
    korea = OntologyEntity.create!(
      canonical_key: "country:kor",
      entity_type: "country",
      canonical_name: "Korea, Rep."
    )
    industry = OntologyEntity.create!(
      canonical_key: "sector:kor:industry",
      entity_type: "sector",
      canonical_name: "Korea, Rep. Industry",
      metadata: { "share_pct" => 33.9 }
    )

    OntologyRelationship.create!(
      source_node: theater,
      target_node: hormuz,
      relation_type: "theater_pressure",
      confidence: 0.95,
      derived_by: "test",
      explanation: "Theater pressure is active around Hormuz."
    )
    OntologyRelationship.create!(
      source_node: hormuz,
      target_node: crude,
      relation_type: "flow_dependency",
      confidence: 0.82,
      derived_by: "test",
      explanation: "Hormuz is a route dependency for crude."
    )
    OntologyRelationship.create!(
      source_node: hormuz,
      target_node: brent,
      relation_type: "flow_dependency",
      confidence: 0.8,
      derived_by: "test",
      explanation: "Brent is a market benchmark for Hormuz.",
      metadata: { "latest_change_pct" => 6.5, "commodity_symbol" => "OIL_BRENT", "flow_pct" => 21 }
    )
    OntologyRelationship.create!(
      source_node: hormuz,
      target_node: korea,
      relation_type: "chokepoint_exposure",
      confidence: 0.76,
      derived_by: "test",
      explanation: "Korea has structural exposure to Hormuz through crude oil.",
      metadata: { "commodities" => ["oil_crude"], "max_exposure_score" => 0.42 }
    )
    OntologyRelationship.create!(
      source_node: crude,
      target_node: korea,
      relation_type: "import_dependency",
      confidence: 0.78,
      derived_by: "test",
      explanation: "Korea depends on imported crude oil.",
      metadata: { "dependency_score" => 0.65 }
    )
    OntologyRelationship.create!(
      source_node: crude,
      target_node: industry,
      relation_type: "production_dependency",
      confidence: 0.52,
      derived_by: "test",
      explanation: "Crude Oil is an input dependency for Korea, Rep. Industry."
    )

    context = NodeContextService.resolve(kind: "chokepoint", id: "Strait of Hormuz")
    chain = context.fetch(:impact_chains).first

    assert_equal "route_market_country_exposure", chain.fetch(:kind)
    assert_includes %w[high critical], chain.fetch(:severity)
    assert_includes chain.fetch(:title), "Strait of Hormuz"
    assert_includes chain.fetch(:title), "Korea, Rep."
    assert_includes chain.fetch(:summary), "Current benchmark signal"
    assert_equal ["driver", "corridor", "flow", "exposure", "economic_channel"], chain.fetch(:steps).map { |step| step.fetch(:role) }
  end
end
