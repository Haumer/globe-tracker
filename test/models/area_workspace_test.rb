require "test_helper"

class AreaWorkspaceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "awtest@example.com", password: "password123")
    @workspace = AreaWorkspace.create!(
      user: @user,
      name: "Test Workspace",
      scope_type: "bbox",
      bounds: { lamin: 34.0, lamax: 36.0, lomin: -119.0, lomax: -117.0 },
      profile: "general"
    )
  end

  test "valid workspace creation" do
    assert @workspace.persisted?
  end

  test "name is required" do
    ws = AreaWorkspace.new(user: @user, name: nil, scope_type: "bbox", bounds: { lamin: 0, lamax: 1, lomin: 0, lomax: 1 })
    assert_not ws.valid?
    assert_includes ws.errors[:name], "can't be blank"
  end

  test "name max length is 120" do
    ws = AreaWorkspace.new(user: @user, name: "x" * 121, scope_type: "bbox", bounds: { lamin: 0, lamax: 1, lomin: 0, lomax: 1 })
    assert_not ws.valid?
    assert ws.errors[:name].any?
  end

  test "scope_type must be valid" do
    ws = AreaWorkspace.new(user: @user, name: "Test", scope_type: "invalid", bounds: { lamin: 0, lamax: 1, lomin: 0, lomax: 1 })
    assert_not ws.valid?
    assert ws.errors[:scope_type].any?
  end

  test "profile must be valid" do
    ws = AreaWorkspace.new(user: @user, name: "Test", scope_type: "bbox", profile: "invalid", bounds: { lamin: 0, lamax: 1, lomin: 0, lomax: 1 })
    assert_not ws.valid?
    assert ws.errors[:profile].any?
  end

  test "bounds must include all required keys" do
    ws = AreaWorkspace.new(user: @user, name: "Test", scope_type: "bbox", bounds: { lamin: 0 })
    assert_not ws.valid?
    assert ws.errors[:bounds].any?
  end

  test "bounds must define valid bounding box" do
    ws = AreaWorkspace.new(user: @user, name: "Test", scope_type: "bbox", bounds: { lamin: 10, lamax: 5, lomin: 0, lomax: 1 })
    assert_not ws.valid?
    assert_includes ws.errors[:bounds], "must define a valid bounding box"
  end

  test "belongs_to user" do
    assert_equal @user, @workspace.user
  end

  test "recent scope orders by updated_at desc" do
    older = AreaWorkspace.create!(user: @user, name: "Older", scope_type: "bbox", bounds: { lamin: 0, lamax: 1, lomin: 0, lomax: 1 })
    older.update!(updated_at: 1.day.ago)
    results = AreaWorkspace.recent
    assert_equal @workspace, results.first
  end

  test "bounds_hash returns indifferent hash with float values" do
    h = @workspace.bounds_hash
    assert_equal 34.0, h[:lamin]
    assert_equal 36.0, h[:lamax]
  end

  test "scope_label returns human readable label" do
    assert_equal "Custom Area", @workspace.scope_label

    @workspace.scope_type = "preset_region"
    assert_equal "Preset Region", @workspace.scope_label

    @workspace.scope_type = "country_set"
    assert_equal "Country Selection", @workspace.scope_label
  end

  test "scope_detail for bbox" do
    assert_equal "Saved from a custom globe area.", @workspace.scope_detail
  end

  test "scope_detail for bbox with radius_km" do
    @workspace.scope_metadata = { radius_km: 100 }
    @workspace.save!
    assert_equal "Drawn circle with a 100 km radius.", @workspace.scope_detail
  end

  test "profile_label titleizes profile" do
    assert_equal "General", @workspace.profile_label
    @workspace.profile = "land_conflict"
    assert_equal "Land Conflict", @workspace.profile_label
  end

  test "layer_labels returns titleized layer names" do
    @workspace.update!(default_layers: ["earthquakes", "militaryBases"])
    labels = @workspace.layer_labels
    assert_includes labels, "Earthquakes"
    assert_includes labels, "Military Bases"
  end

  test "bounds_label formats coordinates" do
    label = @workspace.bounds_label
    assert_match(/34\.00 to 36\.00 lat/, label)
  end

  test "bounds_label returns Unavailable when blank" do
    @workspace.bounds = {}
    assert_equal "Unavailable", @workspace.bounds_label
  end

  test "normalize_json_fields callback stringifies keys" do
    ws = AreaWorkspace.new(
      user: @user, name: "Test", scope_type: "bbox",
      bounds: { lamin: 0, lamax: 1, lomin: 0, lomax: 1 },
      scope_metadata: { region_name: "Test" },
      default_layers: ["a", "", "a", "b"]
    )
    ws.valid?
    assert_equal ["a", "b"], ws.default_layers
  end

  test "country_names returns array from scope_metadata" do
    @workspace.update!(scope_type: "country_set", scope_metadata: { countries: ["US", "DE"] })
    assert_equal ["US", "DE"], @workspace.country_names
  end

  test "region_name returns from scope_metadata" do
    @workspace.update!(scope_type: "preset_region", scope_metadata: { region_name: "Middle East" })
    assert_equal "Middle East", @workspace.region_name
  end
end
