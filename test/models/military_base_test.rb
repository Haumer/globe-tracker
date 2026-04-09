require "test_helper"

class MilitaryBaseTest < ActiveSupport::TestCase
  setup do
    @base = MilitaryBase.create!(
      external_id: "mb-001",
      name: "Camp Test",
      base_type: "army",
      country: "US",
      latitude: 38.0,
      longitude: -77.0
    )
  end

  test "valid creation" do
    assert @base.persisted?
  end

  test "in_bbox scope filters by bounding box" do
    results = MilitaryBase.in_bbox(north: 39.0, south: 37.0, east: -76.0, west: -78.0)
    assert_includes results, @base

    results = MilitaryBase.in_bbox(north: 50.0, south: 49.0, east: 10.0, west: 9.0)
    assert_not_includes results, @base
  end

  test "within_bounds from BoundsFilterable" do
    results = MilitaryBase.within_bounds(lamin: 37.0, lamax: 39.0, lomin: -78.0, lomax: -76.0)
    assert_includes results, @base
  end
end
