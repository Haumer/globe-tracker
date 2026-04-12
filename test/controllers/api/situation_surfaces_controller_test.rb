require "test_helper"

class Api::SituationSurfacesControllerTest < ActionDispatch::IntegrationTest
  test "index returns experimental situation surfaces" do
    payload = {
      surfaces: [
        {
          id: "zone:test",
          label: "Test surface",
          situation_class: "kinetic_conflict",
          severity_tier: "high",
          scope: "local",
          geometry_type: "polygon",
          geometry: { source: "test", rings: [[[1, 1], [1, 2], [2, 2], [2, 1]]] },
        },
      ],
      count: 1,
      generated_at: Time.current.iso8601,
      snapshot_status: "ready",
    }

    SituationSurfaceService.stub(:build, payload) do
      get "/api/situation_surfaces"
    end

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data["count"]
    assert_equal "ready", data["snapshot_status"]
    assert_equal "Test surface", data["surfaces"].first["label"]
  end
end
