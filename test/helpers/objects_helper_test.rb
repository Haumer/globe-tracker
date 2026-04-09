require "test_helper"

class ObjectsHelperTest < ActionView::TestCase
  include ObjectsHelper

  # object_view_request_for_node

  test "object_view_request_for_node returns nil for nil" do
    assert_nil object_view_request_for_node(nil)
  end

  test "object_view_request_for_node returns theater for entity theater" do
    node = { node_type: "entity", entity_type: "theater", canonical_key: "ukraine", name: "Ukraine" }
    result = object_view_request_for_node(node)
    assert_equal({ kind: "theater", id: "ukraine" }, result)
  end

  test "object_view_request_for_node returns commodity for entity commodity" do
    node = { node_type: "entity", entity_type: "commodity", canonical_key: "oil", name: "Oil" }
    result = object_view_request_for_node(node)
    assert_equal({ kind: "commodity", id: "oil" }, result)
  end

  test "object_view_request_for_node returns chokepoint for corridor entity" do
    node = { node_type: "entity", entity_type: "corridor", canonical_key: "corridor:chokepoint:suez" }
    result = object_view_request_for_node(node)
    assert_equal({ kind: "chokepoint", id: "suez" }, result)
  end

  test "object_view_request_for_node returns entity for generic entity with key" do
    node = { node_type: "entity", entity_type: "org", canonical_key: "nato" }
    result = object_view_request_for_node(node)
    assert_equal({ kind: "entity", id: "nato" }, result)
  end

  test "object_view_request_for_node returns news_story_cluster for event" do
    node = { node_type: "event", canonical_key: "news-story-cluster:abc-123" }
    result = object_view_request_for_node(node)
    assert_equal({ kind: "news_story_cluster", id: "abc-123" }, result)
  end

  test "object_view_request_for_node returns nil for unknown type" do
    node = { node_type: "unknown", canonical_key: "something" }
    assert_nil object_view_request_for_node(node)
  end

  # object_view_request_for_evidence

  test "object_view_request_for_evidence returns nil for nil" do
    assert_nil object_view_request_for_evidence(nil)
  end

  test "object_view_request_for_evidence returns news_story_cluster" do
    evidence = { type: "news_story_cluster", cluster_key: "cluster-42" }
    result = object_view_request_for_evidence(evidence)
    assert_equal({ kind: "news_story_cluster", id: "cluster-42" }, result)
  end

  test "object_view_request_for_evidence returns commodity" do
    evidence = { type: "commodity_price", symbol: "GC=F" }
    result = object_view_request_for_evidence(evidence)
    assert_equal({ kind: "commodity", id: "GC=F" }, result)
  end

  test "object_view_request_for_evidence returns nil for unknown type" do
    evidence = { type: "unknown" }
    assert_nil object_view_request_for_evidence(evidence)
  end

  # object_view_href_for

  test "object_view_href_for returns nil for nil request" do
    assert_nil object_view_href_for(nil)
  end

  test "object_view_href_for returns path for valid request" do
    result = object_view_href_for(kind: "theater", id: "ukraine")
    assert_equal "/objects/theater/ukraine", result
  end

  # object_relation_label / object_role_label

  test "object_relation_label humanizes underscored value" do
    assert_equal "Supply Route", object_relation_label("supply_route")
    assert_equal "Trade Partner", object_relation_label("trade_partner")
  end

  test "object_role_label humanizes underscored value" do
    assert_equal "Primary Source", object_role_label("primary_source")
  end

  # object_confidence_label

  test "object_confidence_label returns dash for blank" do
    assert_equal "\u2014", object_confidence_label(nil)
    assert_equal "\u2014", object_confidence_label("")
  end

  test "object_confidence_label formats high confidence without decimal" do
    assert_equal "100%", object_confidence_label(1.0)
    assert_equal "95%", object_confidence_label(0.95)
  end

  test "object_confidence_label formats lower confidence with one decimal" do
    assert_equal "85.0%", object_confidence_label(0.85)
    assert_equal "50.0%", object_confidence_label(0.5)
  end

  # default_case_title_for

  test "default_case_title_for uses node name" do
    context = { node: { name: "Ukraine" } }
    assert_equal "Ukraine case", default_case_title_for(context)
  end

  test "default_case_title_for uses fallback when no name" do
    assert_equal "Untitled Object case", default_case_title_for({})
    assert_equal "Untitled Object case", default_case_title_for({ node: {} })
  end

  # case_source_payload_for

  test "case_source_payload_for builds payload from request and context" do
    request = { kind: "theater", id: "ukraine" }
    context = {
      node: { name: "Ukraine", canonical_key: "ukraine", node_type: "entity", entity_type: "theater", latitude: 48.3, longitude: 31.2 },
      relationships: [1, 2],
      evidence: [1],
      memberships: [],
    }
    payload = case_source_payload_for(request, context)

    assert_equal "theater", payload[:object_kind]
    assert_equal "ukraine", payload[:object_identifier]
    assert_equal "Ukraine", payload[:title]
    assert_equal "theater", payload[:object_type]
    assert_equal 48.3, payload[:latitude]
    assert_equal 2, payload[:source_context][:relationship_count]
    assert_equal 1, payload[:source_context][:evidence_count]
  end
end
