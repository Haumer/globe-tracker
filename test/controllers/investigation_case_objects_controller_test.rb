require "test_helper"

class InvestigationCaseObjectsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "case-objects@example.com", password: "password123")
    @investigation_case = @user.investigation_cases.create!(title: "Maritime watch")
    sign_in @user
  end

  test "POST /case_objects adds an object to an existing case" do
    post case_objects_path, params: {
      case_object: {
        investigation_case_id: @investigation_case.id,
        object_kind: "chokepoint",
        object_identifier: "Suez Canal",
        title: "Suez Canal",
        summary: "Critical trade corridor",
        object_type: "corridor",
        source_context: {
          relationship_count: "3",
          evidence_count: "2",
        }
      }
    }

    assert_redirected_to case_path(@investigation_case)
    assert_equal 1, @investigation_case.case_objects.count
    assert_equal "Suez Canal", @investigation_case.case_objects.first.title
  end
end
