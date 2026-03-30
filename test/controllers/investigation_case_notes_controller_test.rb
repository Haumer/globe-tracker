require "test_helper"

class InvestigationCaseNotesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "case-notes@example.com", password: "password123")
    @investigation_case = @user.investigation_cases.create!(title: "Energy watch")
    sign_in @user
  end

  test "POST /cases/:id/notes creates a note" do
    post case_notes_path(@investigation_case), params: {
      investigation_case_note: {
        body: "Monitor Brent, LNG, and Red Sea exposure.",
        kind: "note",
      }
    }

    assert_redirected_to case_path(@investigation_case)
    assert_equal 1, @investigation_case.case_notes.count
    assert_equal "Monitor Brent, LNG, and Red Sea exposure.", @investigation_case.case_notes.first.body
  end
end
