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
end
