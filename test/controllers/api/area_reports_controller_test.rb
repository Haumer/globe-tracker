require "test_helper"

class Api::AreaReportsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/area_report returns json" do
    assert_difference "LayerSnapshot.where(snapshot_type: 'area_report').count", 1 do
      get "/api/area_report", params: { lamin: 35.0, lamax: 40.0, lomin: -120.0, lomax: -115.0 }
      assert_response :success
      data = JSON.parse(response.body)
      assert_kind_of Hash, data
      assert_equal "ready", data["snapshot_status"]
    end
  end

  test "GET /api/area_report without bounds returns 422" do
    get "/api/area_report"
    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert data["error"].include?("bounding box")
  end
end
