require "test_helper"

class Api::PipelinesControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/pipelines returns pipeline data" do
    Pipeline.create!(
      pipeline_id: "pipe-001",
      name: "Nord Stream",
      pipeline_type: "gas",
      status: "active",
      length_km: 1224.0,
      coordinates: [[10.0, 55.0], [12.0, 54.0]],
      color: "#ff0000",
      country: "Germany"
    )

    get "/api/pipelines"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data["pipelines"]
    assert_equal 1, data["pipelines"].size
    assert_equal "Nord Stream", data["pipelines"].first["name"]
  end

  test "GET /api/pipelines with empty DB returns empty array" do
    get "/api/pipelines"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal [], data["pipelines"]
  end
end
