require "test_helper"

class SubmarineCableTest < ActiveSupport::TestCase
  test "creation with basic fields" do
    cable = SubmarineCable.create!(
      cable_id: "cable-001",
      name: "Transatlantic Express",
      color: "#ff0000",
      coordinates: [[-60.0, 10.0], [-59.5, 10.2]],
      landing_points: [{ "lat" => 10.0, "lng" => -60.0 }]
    )
    assert cable.persisted?
    assert_equal "Transatlantic Express", cable.name
  end

  test "coordinates stored as JSONB" do
    coords = [[-60.0, 10.0], [-59.5, 10.2], [-59.0, 10.5]]
    cable = SubmarineCable.create!(cable_id: "cable-002", name: "Test", coordinates: coords)
    cable.reload
    assert_equal coords, cable.coordinates
  end

  test "unique constraint on cable_id" do
    SubmarineCable.create!(cable_id: "cable-unique", name: "First")
    assert_raises(ActiveRecord::RecordNotUnique) do
      SubmarineCable.create!(cable_id: "cable-unique", name: "Duplicate")
    end
  end

  test "landing_points stored as JSONB" do
    lps = [{ "lat" => 10.0, "lng" => -60.0, "name" => "Port A" }, { "lat" => 50.0, "lng" => -1.0, "name" => "Port B" }]
    cable = SubmarineCable.create!(cable_id: "cable-003", name: "With Landing", landing_points: lps)
    cable.reload
    assert_equal 2, cable.landing_points.size
    assert_equal "Port A", cable.landing_points.first["name"]
  end
end
