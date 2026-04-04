require "test_helper"

class InvestigationCasesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "cases@example.com", password: "password123")
    @other_user = User.create!(email: "analyst@example.com", password: "password123")
    sign_in @user
  end

  test "GET /cases/new preloads source object intake" do
    get new_case_path, params: {
      return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#10,20,300000",
      source_object: {
        object_kind: "theater",
        object_identifier: "Iran Theater",
        title: "Iran Theater",
        summary: "Regional pressure and corroborating signals",
        object_type: "theater",
        source_context: {
          severity: "high",
          pulse_score: "73",
        }
      }
    }

    assert_response :success
    assert_includes response.body, "Start a working case"
    assert_includes response.body, "Iran Theater"
    assert_includes response.body, "Create New Case"
    assert_includes response.body, "Add To Existing Case"
    assert_includes response.body, "Return To Globe"
    assert_includes response.body, "return_to"
  end

  test "POST /cases creates a case with a pinned source object and preserves globe return state" do
    post cases_path, params: {
      return_to: "/?focus_kind=chokepoint&focus_id=Strait%20of%20Hormuz#25.5,56.2,1400000",
      investigation_case: {
        title: "Hormuz monitoring",
        summary: "Track pressure on the corridor and supporting evidence.",
        status: "open",
        severity: "high",
        assignee_id: @other_user.id,
      },
      source_object: {
        object_kind: "chokepoint",
        object_identifier: "Strait of Hormuz",
        title: "Strait of Hormuz",
        summary: "Strategic energy corridor",
        object_type: "corridor",
        latitude: "26.56",
        longitude: "56.27",
        source_context: {
          relationship_count: "2",
          evidence_count: "4",
          membership_count: "0",
        }
      }
    }

    investigation_case = InvestigationCase.order(:id).last
    assert_redirected_to case_path(investigation_case, return_to: "/?focus_kind=chokepoint&focus_id=Strait%20of%20Hormuz#25.5,56.2,1400000")
    assert_equal "Hormuz monitoring", investigation_case.title
    assert_equal "high", investigation_case.severity
    assert_equal @other_user, investigation_case.assignee
    assert_equal 1, investigation_case.case_objects.count
    assert_equal "Strait of Hormuz", investigation_case.case_objects.first.title
  end

  test "GET /cases/:id shows pinned objects and notes" do
    investigation_case = @user.investigation_cases.create!(
      title: "Iran theater watch",
      status: "monitoring",
      severity: "critical",
      summary: "Track theater escalation and regional chokepoint pressure."
    )
    investigation_case.case_objects.create!(
      object_kind: "theater",
      object_identifier: "Iran Theater",
      title: "Iran Theater",
      summary: "Derived conflict theater bubble",
      object_type: "theater"
    )
    investigation_case.case_notes.create!(user: @user, body: "Start with Hormuz, Bahrain, and Suez.")

    get case_path(investigation_case), params: { return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#12,43,1200000" }

    assert_response :success
    assert_includes response.body, "Iran theater watch"
    assert_includes response.body, "Pinned Objects"
    assert_includes response.body, "Iran Theater"
    assert_includes response.body, "Start with Hormuz, Bahrain, and Suez."
    assert_includes response.body, "Add Note"
    assert_includes response.body, "Return To Globe"
  end

  test "PATCH /cases/:id updates status severity and assignee while preserving globe return state" do
    investigation_case = @user.investigation_cases.create!(
      title: "Iran theater watch",
      status: "open",
      severity: "medium",
      assignee: @user
    )

    patch case_path(investigation_case), params: {
      return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#12,43,1200000",
      investigation_case: {
        status: "escalated",
        severity: "critical",
        assignee_id: @other_user.id,
        summary: "Move to active escalation tracking."
      }
    }

    assert_redirected_to case_path(investigation_case, return_to: "/?focus_kind=theater&focus_id=Iran%20Theater#12,43,1200000")
    investigation_case.reload
    assert_equal "escalated", investigation_case.status
    assert_equal "critical", investigation_case.severity
    assert_equal @other_user, investigation_case.assignee
    assert_equal "Move to active escalation tracking.", investigation_case.summary
  end
end
