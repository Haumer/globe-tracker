require "test_helper"

class PurgeStaleDataJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", PurgeStaleDataJob.new.queue_name
  end

  test "runs without error" do
    # The job calls delete_all on multiple models; just verify it runs
    assert_nothing_raised do
      PurgeStaleDataJob.perform_now
    end
  end

  test "retains historical position snapshots beyond the old three day window" do
    retained = PositionSnapshot.create!(
      entity_type: "flight",
      entity_id: "retained-baseline-flight",
      latitude: 48.0,
      longitude: 16.0,
      recorded_at: 10.days.ago
    )
    stale = PositionSnapshot.create!(
      entity_type: "flight",
      entity_id: "stale-baseline-flight",
      latitude: 48.0,
      longitude: 16.0,
      recorded_at: 20.days.ago
    )

    PurgeStaleDataJob.perform_now

    assert PositionSnapshot.exists?(retained.id)
    refute PositionSnapshot.exists?(stale.id)
  end
end
