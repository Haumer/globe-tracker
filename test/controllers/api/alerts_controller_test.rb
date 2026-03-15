require "test_helper"

class Api::AlertsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "alerts@example.com", password: "password123")
    sign_in @user
    @watch = Watch.create!(user: @user, name: "Test Watch", watch_type: "area", cooldown_minutes: 15)
    @alert = Alert.create!(
      user: @user,
      watch: @watch,
      title: "Earthquake near zone",
      details: { magnitude: 5.2 },
      entity_type: "earthquake",
      entity_id: "eq123",
      lat: 35.0,
      lng: -118.0,
      seen: false
    )
  end

  test "GET /api/alerts returns unseen alerts" do
    get "/api/alerts"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Integer, data["unseen_count"]
    assert_kind_of Array, data["alerts"]
  end

  test "PATCH /api/alerts/:id marks alert as seen" do
    patch "/api/alerts/#{@alert.id}", params: { seen: true }
    assert_response :no_content
    assert @alert.reload.seen
  end

  test "POST /api/alerts/mark_all_seen marks all unseen alerts" do
    Alert.create!(user: @user, title: "Second alert", seen: false)
    post "/api/alerts/mark_all_seen"
    assert_response :no_content
    assert_equal 0, @user.alerts.unseen.count
  end

  test "unauthenticated request is redirected" do
    sign_out @user
    get "/api/alerts"
    assert_response :redirect
  end
end
