require "test_helper"

class InvestigationCaseNoteTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "notetest@example.com", password: "password123")
    @case = InvestigationCase.create!(user: @user, title: "Test case")
    @note = InvestigationCaseNote.create!(
      investigation_case: @case,
      user: @user,
      body: "Initial assessment complete.",
      kind: "note"
    )
  end

  test "valid creation" do
    assert @note.persisted?
  end

  test "body is required" do
    r = InvestigationCaseNote.new(investigation_case: @case, user: @user, kind: "note")
    assert_not r.valid?
    assert_includes r.errors[:body], "can't be blank"
  end

  test "body max length is 10000" do
    r = InvestigationCaseNote.new(investigation_case: @case, user: @user, body: "x" * 10_001, kind: "note")
    assert_not r.valid?
    assert r.errors[:body].any?
  end

  test "kind must be valid" do
    r = InvestigationCaseNote.new(investigation_case: @case, user: @user, body: "Test", kind: "invalid")
    assert_not r.valid?
    assert r.errors[:kind].any?
  end

  test "all valid kinds are accepted" do
    %w[note update decision brief].each do |k|
      r = InvestigationCaseNote.new(investigation_case: @case, user: @user, body: "Test", kind: k)
      assert r.valid?, "kind '#{k}' should be valid"
    end
  end

  test "belongs_to investigation_case" do
    assert_equal @case, @note.investigation_case
  end

  test "belongs_to user" do
    assert_equal @user, @note.user
  end
end
