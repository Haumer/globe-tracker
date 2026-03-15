require "test_helper"

class Api::TrendingControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/trending returns json array" do
    get "/api/trending"
    assert_response :success
    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end
end
