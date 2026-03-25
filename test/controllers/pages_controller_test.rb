require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "sources page lists pending and deprecated source inventory entries" do
    get "/sources"

    assert_response :success
    assert_includes response.body, "ReliefWeb"
    assert_includes response.body, "Media Cloud"
    assert_includes response.body, "Legacy Reuters RSS"
    assert_includes response.body, "PENDING"
    assert_includes response.body, "DEPRECATED"
  end
end
