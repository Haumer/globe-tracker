require "test_helper"

class OntologyRelationshipEvidenceTest < ActiveSupport::TestCase
  setup do
    @entity1 = OntologyEntity.create!(
      canonical_key: "re-entity-1", entity_type: "state", canonical_name: "Russia"
    )
    @entity2 = OntologyEntity.create!(
      canonical_key: "re-entity-2", entity_type: "state", canonical_name: "Ukraine"
    )
    @rel = OntologyRelationship.create!(
      source_node: @entity1, target_node: @entity2,
      relation_type: "adversary", derived_by: "sync"
    )
    @cluster = NewsStoryCluster.create!(
      cluster_key: "re-cluster-001", content_scope: "core", event_family: "conflict",
      event_type: "strike", geo_precision: "unknown",
      first_seen_at: Time.current, last_seen_at: Time.current,
      verification_status: "single_source"
    )
    @evidence = OntologyRelationshipEvidence.create!(
      ontology_relationship: @rel, evidence: @cluster, evidence_role: "supporting"
    )
  end

  test "valid creation" do
    assert @evidence.persisted?
  end

  test "evidence_role is required" do
    r = OntologyRelationshipEvidence.new(ontology_relationship: @rel, evidence: @cluster)
    r.evidence_role = nil
    assert_not r.valid?
    assert_includes r.errors[:evidence_role], "can't be blank"
  end

  test "belongs_to ontology_relationship" do
    assert_equal @rel, @evidence.ontology_relationship
  end

  test "belongs_to evidence polymorphic" do
    assert_equal @cluster, @evidence.evidence
  end
end
