require "test_helper"

class Api::WorkspacesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "workspaces@example.com", password: "password123")
    sign_in @user
  end

  test "GET /api/workspaces returns user workspaces" do
    Workspace.create!(user: @user, name: "Default", is_default: true)

    get "/api/workspaces"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert_equal 1, data.size
    assert_equal "Default", data.first["name"]
  end

  test "POST /api/workspaces creates a workspace" do
    post "/api/workspaces", params: {
      name: "My Workspace",
      camera_lat: 48.2,
      camera_lng: 16.3,
      camera_height: 1000000.0
    }
    assert_response :created

    data = JSON.parse(response.body)
    assert_equal "My Workspace", data["name"]
    assert_in_delta 48.2, data["camera_lat"], 0.01
  end

  test "PATCH /api/workspaces/:id updates a workspace" do
    ws = Workspace.create!(user: @user, name: "Old Name")
    patch "/api/workspaces/#{ws.id}", params: { name: "New Name" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "New Name", data["name"]
  end

  test "DELETE /api/workspaces/:id destroys a workspace" do
    ws = Workspace.create!(user: @user, name: "To Delete")
    delete "/api/workspaces/#{ws.id}"
    assert_response :no_content
    assert_not Workspace.exists?(ws.id)
  end

  test "unauthenticated request is redirected" do
    sign_out @user
    get "/api/workspaces"
    assert_response :redirect
  end
end
