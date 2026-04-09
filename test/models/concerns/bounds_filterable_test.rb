require "test_helper"

class BoundsFilterableTest < ActiveSupport::TestCase
  setup do
    Earthquake.where(external_id: %w[bf-in bf-out]).delete_all

    @inside = Earthquake.create!(
      external_id: "bf-in",
      title: "Inside bounds",
      magnitude: 3.0,
      latitude: 40.0,
      longitude: -100.0,
      depth: 5.0,
      event_time: 1.hour.ago,
      fetched_at: Time.current,
    )
    @outside = Earthquake.create!(
      external_id: "bf-out",
      title: "Outside bounds",
      magnitude: 3.0,
      latitude: 10.0,
      longitude: 10.0,
      depth: 5.0,
      event_time: 1.hour.ago,
      fetched_at: Time.current,
    )
  end

  test "within_bounds returns records inside bounds" do
    bounds = { lamin: 39.0, lamax: 41.0, lomin: -101.0, lomax: -99.0 }
    results = Earthquake.within_bounds(bounds)
    assert_includes results, @inside
    assert_not_includes results, @outside
  end

  test "within_bounds returns all records when bounds are nil" do
    results = Earthquake.within_bounds(nil)
    assert_includes results, @inside
    assert_includes results, @outside
  end

  test "within_bounds returns all records when bounds are empty" do
    results = Earthquake.within_bounds({})
    assert_includes results, @inside
    assert_includes results, @outside
  end

  test "within_bounds returns all records when bounds have fewer than 4 keys" do
    results = Earthquake.within_bounds({ lamin: 39.0, lamax: 41.0 })
    assert_includes results, @inside
    assert_includes results, @outside
  end
end
