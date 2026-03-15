require "test_helper"

class Api::AnomaliesControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/anomalies returns json" do
    get "/api/anomalies"
    assert_response :success
    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end
end
