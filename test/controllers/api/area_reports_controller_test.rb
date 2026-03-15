require "test_helper"

class Api::AreaReportsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/area_report returns json" do
    get "/api/area_report", params: { lamin: 35.0, lamax: 40.0, lomin: -120.0, lomax: -115.0 }
    assert_response :success
    data = JSON.parse(response.body)
    assert_kind_of Hash, data
  end

  test "GET /api/area_report without bounds still succeeds" do
    get "/api/area_report"
    assert_response :success
  end
end
