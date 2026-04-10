require "test_helper"

class Api::GeographyBoundariesControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/geography/boundaries returns requested dataset" do
    payload = {
      "type" => "FeatureCollection",
      "features" => [
        {
          "type" => "Feature",
          "geometry" => { "type" => "Polygon", "coordinates" => [[[10.0, 45.0], [11.0, 45.0], [11.0, 46.0], [10.0, 45.0]]] },
          "properties" => { "name" => "Stub Boundary" },
        },
      ],
    }

    GeographyBoundaryService.stub(:fetch, payload) do
      get "/api/geography/boundaries", params: { dataset: "admin1" }
    end

    assert_response :success
    assert_match "application/json", response.content_type

    data = JSON.parse(response.body)
    assert_equal "FeatureCollection", data["type"]
    assert_equal 1, data["features"].size
  end

  test "GET /api/geography/boundaries rejects unsupported datasets" do
    get "/api/geography/boundaries", params: { dataset: "districts" }

    assert_response :unprocessable_content
    data = JSON.parse(response.body)
    assert_equal "Unsupported boundary dataset", data["error"]
    assert_includes data["allowed_datasets"], "countries"
    assert_includes data["allowed_datasets"], "admin1"
  end

  test "GET /api/geography/boundaries returns unavailable when fetch fails" do
    GeographyBoundaryService.stub(:fetch, nil) do
      get "/api/geography/boundaries", params: { dataset: "countries" }
    end

    assert_response :service_unavailable
    data = JSON.parse(response.body)
    assert_equal "Boundary dataset unavailable", data["error"]
    assert_equal "countries", data["dataset"]
  end
end
