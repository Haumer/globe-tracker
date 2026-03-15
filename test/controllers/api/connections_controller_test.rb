require "test_helper"

class Api::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/connections returns JSON" do
    get "/api/connections", params: { entity_type: "flight", lat: "48.2", lng: "16.3" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Hash, data
  end

  test "connections with metadata param" do
    get "/api/connections", params: {
      entity_type: "flight",
      lat: "48.2",
      lng: "16.3",
      metadata: { callsign: "TEST01" }
    }
    assert_response :success
  end
end
