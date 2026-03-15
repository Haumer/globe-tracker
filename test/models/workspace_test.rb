require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "wstest@example.com", password: "password123")
    @workspace = Workspace.create!(
      user: @user,
      name: "My Workspace",
      camera_lat: 48.2,
      camera_lng: 16.3,
      camera_height: 5000000,
      is_default: false,
      shared: false,
    )
  end

  test "valid workspace creation" do
    assert @workspace.persisted?
    assert_equal "My Workspace", @workspace.name
  end

  test "name is required" do
    ws = Workspace.new(user: @user, name: nil)
    assert_not ws.valid?
    assert_includes ws.errors[:name], "can't be blank"
  end

  test "name max length is 100" do
    ws = Workspace.new(user: @user, name: "a" * 101)
    assert_not ws.valid?
    assert ws.errors[:name].any?
  end

  test "slug must be unique" do
    Workspace.create!(user: @user, name: "Shared One", shared: true, slug: "shared-one")
    ws2 = Workspace.new(user: @user, name: "Another", shared: true, slug: "shared-one")
    assert_not ws2.valid?
  end

  test "shared workspace generates slug on save" do
    ws = Workspace.create!(user: @user, name: "Public View", shared: true)
    assert_not_nil ws.slug
    assert_equal "public-view", ws.slug
  end

  test "non-shared workspace clears slug" do
    ws = Workspace.create!(user: @user, name: "Private", shared: true)
    assert_not_nil ws.slug
    ws.update!(shared: false)
    assert_nil ws.slug
  end

  test "ordered scope puts defaults first" do
    default_ws = Workspace.create!(user: @user, name: "Default", is_default: true)
    results = @user.workspaces.ordered
    assert_equal default_ws, results.first
  end
end
