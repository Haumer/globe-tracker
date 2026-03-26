require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home page renders the selected context pane" do
    get "/"

    assert_response :success
    assert_includes response.body, "Selected Context"
    assert_includes response.body, "data-rp-pane=\"context\""
  end

  test "sources page lists active source inventory entries without removed placeholders" do
    get "/sources"

    assert_response :success
    assert_includes response.body, "Curated RSS Mesh"
    assert_includes response.body, "Multi-source News APIs"
    refute_includes response.body, "ReliefWeb"
    refute_includes response.body, "Media Cloud"
    refute_includes response.body, "Legacy Reuters RSS"
  end
end
