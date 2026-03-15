require "test_helper"

class Api::InsightsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "insights@example.com", password: "password123")
    sign_in @user
  end

  test "GET /api/insights returns insights array" do
    get "/api/insights"
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("insights")
    assert_kind_of Array, data["insights"]
  end

  test "unauthenticated request is redirected" do
    sign_out @user
    get "/api/insights"
    assert_response :redirect
  end
end
