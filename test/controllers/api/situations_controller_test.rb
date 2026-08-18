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
  end
end
