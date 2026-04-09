require "test_helper"

class InvestigationCaseObjectTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "objtest@example.com", password: "password123")
    @case = InvestigationCase.create!(user: @user, title: "Test case")
    @obj = InvestigationCaseObject.create!(
      investigation_case: @case,
      object_kind: "ship",
      object_identifier: "mmsi-123456789",
      title: "Suspicious Vessel",
      source_context: { evidence_count: 3, relationship_count: 1, membership_count: 0 }
    )
  end

  test "valid creation" do
    assert @obj.persisted?
  end

  test "object_kind is required" do
    r = InvestigationCaseObject.new(investigation_case: @case, object_identifier: "x", title: "T")
    assert_not r.valid?
    assert_includes r.errors[:object_kind], "can't be blank"
  end

  test "object_identifier is required" do
    r = InvestigationCaseObject.new(investigation_case: @case, object_kind: "ship", title: "T")
    assert_not r.valid?
    assert_includes r.errors[:object_identifier], "can't be blank"
  end

  test "title is required" do
    r = InvestigationCaseObject.new(investigation_case: @case, object_kind: "ship", object_identifier: "x")
    assert_not r.valid?
    assert_includes r.errors[:title], "can't be blank"
  end

  test "title max length is 240" do
    r = InvestigationCaseObject.new(investigation_case: @case, object_kind: "ship", object_identifier: "x", title: "x" * 241)
    assert_not r.valid?
    assert r.errors[:title].any?
  end

  test "object_identifier uniqueness scoped to case and kind" do
    dup = InvestigationCaseObject.new(
      investigation_case: @case, object_kind: "ship",
      object_identifier: "mmsi-123456789", title: "Dup"
    )
    assert_not dup.valid?
    assert dup.errors[:object_identifier].any?
  end

  test "same identifier different kind is allowed" do
    other = InvestigationCaseObject.create!(
      investigation_case: @case, object_kind: "flight",
      object_identifier: "mmsi-123456789", title: "Not a dup"
    )
    assert other.persisted?
  end

  test "belongs_to investigation_case" do
    assert_equal @case, @obj.investigation_case
  end

  test "object_request returns kind and id" do
    assert_equal({ kind: "ship", id: "mmsi-123456789" }, @obj.object_request)
  end

  test "evidence_count reads from source_context" do
    assert_equal 3, @obj.evidence_count
  end

  test "relationship_count reads from source_context" do
    assert_equal 1, @obj.relationship_count
  end

  test "membership_count reads from source_context" do
    assert_equal 0, @obj.membership_count
  end

  test "attributes_from_payload normalizes hash" do
    attrs = InvestigationCaseObject.attributes_from_payload(
      object_kind: "ship", object_identifier: "mmsi-999",
      title: "Test", latitude: "48.5", longitude: "35.0"
    )
    assert_equal "ship", attrs[:object_kind]
    assert_equal 48.5, attrs[:latitude]
  end
end
