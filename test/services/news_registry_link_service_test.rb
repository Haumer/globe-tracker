require "test_helper"

class NewsRegistryLinkServiceTest < ActiveSupport::TestCase
  setup do
    @corridor = OntologyEntity.create!(
      canonical_key: "corridor:chokepoint:hormuz", entity_type: "corridor", canonical_name: "Strait of Hormuz"
    )
    OntologyEntityAlias.create!(ontology_entity: @corridor, name: "Hormuz", alias_type: "short_form")
  end

  def cluster_with_event(key:, title:)
    cluster = NewsStoryCluster.create!(
      cluster_key: key, canonical_title: title, event_family: "conflict", event_type: "blockade",
      verification_status: "single_source", geo_precision: "unknown", cluster_confidence: 0.6,
      source_reliability: 0.6, geo_confidence: 0.0,
      first_seen_at: 1.day.ago, last_seen_at: 1.day.ago
    )
    event = OntologyEvent.create!(
      canonical_key: "news-story-cluster:#{key}", primary_story_cluster: cluster,
      event_family: "conflict", event_type: "blockade", last_seen_at: 1.day.ago
    )
    [cluster, event]
  end

  test "links an event to the corridor its headline names" do
    _cluster, event = cluster_with_event(key: "c-hormuz", title: "Iran moves to block shipments from Strait of Hormuz")

    stats = NewsRegistryLinkService.sync_recent

    assert_equal 1, stats[:linked]
    edge = OntologyRelationship.find_by(source_node: event, relation_type: "names_entity")
    assert_equal @corridor, edge.target_node, "this edge is the ring 0 -> ring 3 join"
    assert_equal "strait of hormuz", edge.metadata["surface"]
  end

  test "links through the short-form alias" do
    _cluster, event = cluster_with_event(key: "c-short", title: "Gulf states should make a deal with Iran on Hormuz")

    NewsRegistryLinkService.sync_recent

    assert_equal [@corridor],
      OntologyRelationship.where(source_node: event, relation_type: "names_entity").map(&:target_node)
  end

  # Connectivity is gameable, so the unresolved tier stays unwritten.
  test "does not write a candidate match" do
    OntologyEntity.create!(canonical_key: "port:nagasaki", entity_type: "port", canonical_name: "NAGASAKI")
    _cluster, event = cluster_with_event(key: "c-nag", title: "Taiwan representative skips Nagasaki atomic bombing anniversary")

    NewsRegistryLinkService.sync_recent(resolver: nil)

    assert_empty OntologyRelationship.where(source_node: event, relation_type: "names_entity"),
      "a settlement-named asset is unresolved until 1.4, not a link"
  end

  test "drops an edge the retitled cluster no longer supports" do
    cluster, event = cluster_with_event(key: "c-retitle", title: "Iran moves to block shipments from Strait of Hormuz")
    NewsRegistryLinkService.sync_recent
    assert_equal 1, OntologyRelationship.where(source_node: event, relation_type: "names_entity").count

    cluster.update!(canonical_title: "Talks resume between Iran and Oman")
    NewsRegistryLinkService.sync_recent

    assert_empty OntologyRelationship.where(source_node: event, relation_type: "names_entity")
  end

  # Other services own the actor and affected-party memberships on the same event.
  test "leaves memberships owned by other roles alone" do
    _cluster, event = cluster_with_event(key: "c-roles", title: "Talks resume between Iran and Oman")
    actor = OntologyEntity.create!(canonical_key: "actor:iran", entity_type: "actor", canonical_name: "Iran")
    OntologyEventEntity.create!(ontology_event: event, ontology_entity: actor, role: "initiator")

    NewsRegistryLinkService.sync_recent

    assert_equal ["initiator"], event.ontology_event_entities.reload.map(&:role)
  end

  # Phase 1.4: the tier string matching cannot settle becomes an edge only once
  # the model has picked it out of the candidates.
  test "writes an edge for a candidate the resolver picks" do
    refinery = OntologyEntity.create!(
      canonical_key: "power-plant:jazan", entity_type: "power_plant", canonical_name: "JAZAN",
      country_code: "SA", metadata: { "latitude" => 16.94, "longitude" => 42.633 }
    )
    _cluster, event = cluster_with_event(key: "c-jazan", title: "Houthis attack Saudi Aramco Jazan refinery")
    picker = ->(title:, candidates:) {
      RegistryEntityResolver::Resolution.new(entity_id: candidates.first.entity_id, basis: "refinery")
    }

    NewsRegistryLinkService.sync_recent(resolver: picker)

    edge = OntologyRelationship.find_by(source_node: event, relation_type: "names_entity")
    assert_equal refinery, edge.target_node
    assert_equal 0.75, edge.confidence, "a model judgement is recorded below a named corridor"
  end

  test "writes nothing when the resolver declines" do
    OntologyEntity.create!(canonical_key: "port:nagasaki", entity_type: "port", canonical_name: "NAGASAKI")
    _cluster, event = cluster_with_event(key: "c-decline", title: "Nagasaki marks bombing anniversary")
    decliner = ->(title:, candidates:) { RegistryEntityResolver::NONE }

    NewsRegistryLinkService.sync_recent(resolver: decliner)

    assert_empty OntologyRelationship.where(source_node: event, relation_type: "names_entity")
  end

  test "runs the deterministic tier alone when no resolver is configured" do
    OntologyEntity.create!(canonical_key: "port:nagasaki", entity_type: "port", canonical_name: "NAGASAKI")
    _cluster, event = cluster_with_event(key: "c-noresolver", title: "Nagasaki marks bombing anniversary")

    NewsRegistryLinkService.sync_recent(resolver: nil)

    assert_empty OntologyRelationship.where(source_node: event, relation_type: "names_entity")
  end
end
