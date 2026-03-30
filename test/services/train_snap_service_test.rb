require "test_helper"

class TrainSnapServiceTest < ActiveSupport::TestCase
  setup do
    @railway = Railway.create!(
      category: 1,
      electrified: 1,
      continent: "Europe",
      min_lat: 48.20,
      max_lat: 48.20,
      min_lng: 16.35,
      max_lng: 16.45,
      coordinates: [[16.35, 48.20], [16.45, 48.20]]
    )
  end

  test "snap_all projects nearby trains onto the closest railway segment" do
    result = TrainSnapService.snap_all([
      { id: "rjx-1", lat: 48.20035, lng: 16.39 }
    ])

    snapped = result.fetch("rjx-1")
    assert_equal @railway.id, snapped[:matched_railway_id]
    assert_in_delta 48.20, snapped[:snapped_latitude], 0.00001
    assert_in_delta 16.39, snapped[:snapped_longitude], 0.0001
    assert_equal "high", snapped[:snap_confidence]
  end

  test "snap_all leaves distant trains unsnapped" do
    result = TrainSnapService.snap_all([
      { id: "rjx-2", lat: 49.0, lng: 14.0 }
    ])

    assert_empty result
  end
end
