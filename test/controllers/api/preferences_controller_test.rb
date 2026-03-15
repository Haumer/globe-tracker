require "test_helper"

class Api::PreferencesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "prefs@example.com", password: "password123", preferences: { sidebar_collapsed: false })
    sign_in @user
  end

  test "GET /api/preferences returns user preferences" do
    get "/api/preferences"
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal false, data["sidebar_collapsed"]
  end

  test "PATCH /api/preferences updates preferences" do
    patch "/api/preferences", params: { sidebar_collapsed: true }
    assert_response :success
    assert @user.reload.preferences["sidebar_collapsed"].present?
  end

  test "PATCH /api/preferences merges with existing preferences" do
    patch "/api/preferences", params: { camera_lat: 48.2 }
    assert_response :success
    prefs = @user.reload.preferences
    assert_in_delta 48.2, prefs["camera_lat"].to_f, 0.01
    assert_equal false, prefs["sidebar_collapsed"]
  end

  test "unauthenticated request is redirected" do
    sign_out @user
    get "/api/preferences"
    assert_response :redirect
  end
end
