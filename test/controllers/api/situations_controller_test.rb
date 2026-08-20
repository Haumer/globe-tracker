require "test_helper"

module Api
  class SituationsControllerTest < ActionDispatch::IntegrationTest
    test "serves the board without a session" do
      get api_situations_url

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal SituationBoardService::RINGS.keys.size, 3
      assert body.key?("situations")
      assert body.key?("window_days")
    end

    test "clamps the window so a huge days param cannot walk the whole table" do
      get api_situations_url(days: 9999)

      assert_equal SituationsController::MAX_DAYS, JSON.parse(response.body)["window_days"]
    end

    test "falls back to the default window when days is junk" do
      get api_situations_url(days: "0")

      assert_equal SituationsController::DEFAULT_DAYS, JSON.parse(response.body)["window_days"]
    end

    test "regions dedupes shared features and tags them with every situation" do
      board = { situations: [
        { id: 7, anchor: { lat: 31.5, lng: 34.47 } },
        { id: 3, anchor: { lat: 31.4, lng: 34.4 } },
        { id: 9, anchor: { lat: 26.56, lng: 56.27 } },
      ], window_days: 3 }
      dataset = { "type" => "FeatureCollection", "features" => [
        { "type" => "Feature",
          "properties" => { "name" => "Gaza Strip", "iso_a2" => "PS", "adm0_a3" => "PSE" },
          "geometry" => { "type" => "Polygon",
                          "coordinates" => [ [ [ 34.0, 31.0 ], [ 35.0, 31.0 ], [ 35.0, 32.0 ], [ 34.0, 32.0 ], [ 34.0, 31.0 ] ] ] } },
      ] }

      SituationBoardService.stub(:call, board) do
        GeographyBoundaryService.stub(:fetch, dataset) do
          get "/api/situations/regions"
        end
      end

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body["features"].size, "two situations share one region; the sea anchor gets none"
      feature = body["features"].first
      assert_equal "Gaza Strip", feature["properties"]["name"]
      assert_equal [ 3, 7 ], feature["properties"]["situation_ids"]
    end

    test "regions serves an empty board as an empty collection" do
      SituationBoardService.stub(:call, { situations: [], window_days: 3 }) do
        get "/api/situations/regions"
      end

      assert_response :success
      assert_equal [], JSON.parse(response.body)["features"]
    end
  end
end
