require "test_helper"

class OntologyEvidenceLinkTest < ActiveSupport::TestCase
  setup do
    @event = OntologyEvent.create!(
      canonical_key: "event-evid-001", event_family: "conflict", event_type: "strike",
      status: "active", verification_status: "unverified", geo_precision: "unknown"
    )
    @cluster = NewsStoryCluster.create!(
      cluster_key: "evid-cluster-001", content_scope: "core", event_family: "conflict",
      event_type: "strike", geo_precision: "unknown",
      first_seen_at: Time.current, last_seen_at: Time.current,
      verification_status: "single_source"
    )
    @link = OntologyEvidenceLink.create!(
      ontology_event: @event, evidence: @cluster, evidence_role: "supporting"
    )
  end

  test "valid creation" do
    assert @link.persisted?
  end

  test "evidence_role is required" do
    r = OntologyEvidenceLink.new(ontology_event: @event, evidence: @cluster)
    r.evidence_role = nil
    assert_not r.valid?
    assert_includes r.errors[:evidence_role], "can't be blank"
  end

  test "belongs_to ontology_event" do
    assert_equal @event, @link.ontology_event
  end

  test "belongs_to evidence (polymorphic)" do
    assert_equal @cluster, @link.evidence
  end
end
