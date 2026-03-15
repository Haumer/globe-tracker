require "test_helper"

class Api::WatchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "watches@example.com", password: "password123")
    sign_in @user
  end

  test "GET /api/watches returns user watches" do
    Watch.create!(user: @user, name: "Test Watch", watch_type: "area", cooldown_minutes: 15)

    get "/api/watches"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert_equal 1, data.size
    assert_equal "Test Watch", data.first["name"]
  end

  test "POST /api/watches creates a watch" do
    post "/api/watches", params: { name: "New Watch", watch_type: "entity", cooldown_minutes: 10 }
    assert_response :created

    data = JSON.parse(response.body)
    assert_equal "New Watch", data["name"]
    assert_equal "entity", data["watch_type"]
  end

  test "PATCH /api/watches/:id updates a watch" do
    watch = Watch.create!(user: @user, name: "Old Name", watch_type: "area", cooldown_minutes: 15)

    patch "/api/watches/#{watch.id}", params: { name: "Updated Name" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Updated Name", data["name"]
  end

  test "DELETE /api/watches/:id destroys a watch" do
    watch = Watch.create!(user: @user, name: "To Delete", watch_type: "event", cooldown_minutes: 15)

    delete "/api/watches/#{watch.id}"
    assert_response :no_content
    assert_not Watch.exists?(watch.id)
  end

  test "unauthenticated request is redirected" do
    sign_out @user
    get "/api/watches"
    assert_response :redirect
  end
end
