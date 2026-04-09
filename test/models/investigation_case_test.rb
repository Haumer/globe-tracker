require "test_helper"

class InvestigationCaseTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "casetest@example.com", password: "password123")
    @case = InvestigationCase.create!(
      user: @user,
      title: "Suspicious vessel activity",
      status: "open",
      severity: "high"
    )
  end

  test "valid creation" do
    assert @case.persisted?
  end

  test "title is required" do
    r = InvestigationCase.new(user: @user)
    assert_not r.valid?
    assert_includes r.errors[:title], "can't be blank"
  end

  test "title max length is 140" do
    r = InvestigationCase.new(user: @user, title: "x" * 141)
    assert_not r.valid?
    assert r.errors[:title].any?
  end

  test "summary max length is 5000" do
    r = InvestigationCase.new(user: @user, title: "Test", summary: "x" * 5001)
    assert_not r.valid?
    assert r.errors[:summary].any?
  end

  test "status must be valid" do
    r = InvestigationCase.new(user: @user, title: "Test", status: "invalid")
    assert_not r.valid?
    assert r.errors[:status].any?
  end

  test "severity must be valid" do
    r = InvestigationCase.new(user: @user, title: "Test", severity: "invalid")
    assert_not r.valid?
    assert r.errors[:severity].any?
  end

  test "belongs_to user" do
    assert_equal @user, @case.user
  end

  test "assignee is optional" do
    assert_nil @case.assignee
    assignee = User.create!(email: "assignee@example.com", password: "password123")
    @case.update!(assignee: assignee)
    assert_equal assignee, @case.assignee
  end

  test "has_many case_objects" do
    assert_respond_to @case, :case_objects
  end

  test "has_many case_notes" do
    assert_respond_to @case, :case_notes
  end

  test "case_code returns formatted code" do
    assert_match(/CASE-\d{5}/, @case.case_code)
  end

  test "case_code returns DRAFT when not persisted" do
    r = InvestigationCase.new
    assert_equal "DRAFT", r.case_code
  end

  test "assignee_email returns email when assigned" do
    assignee = User.create!(email: "assigned@example.com", password: "password123")
    @case.update!(assignee: assignee)
    assert_equal "assigned@example.com", @case.assignee_email
  end

  test "assignee_email returns Unassigned when no assignee" do
    assert_equal "Unassigned", @case.assignee_email
  end

  test "recent scope orders by updated_at desc" do
    results = InvestigationCase.recent
    assert_includes results, @case
  end
end
