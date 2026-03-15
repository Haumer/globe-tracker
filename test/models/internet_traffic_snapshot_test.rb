require "test_helper"

class InternetTrafficSnapshotTest < ActiveSupport::TestCase
  setup do
    @now = Time.current
    @snap1 = InternetTrafficSnapshot.create!(
      country_code: "US",
      country_name: "United States",
      traffic_pct: 25.0,
      attack_origin_pct: 10.0,
      attack_target_pct: 5.0,
      recorded_at: @now
    )
    @snap2 = InternetTrafficSnapshot.create!(
      country_code: "DE",
      country_name: "Germany",
      traffic_pct: 8.0,
      attack_origin_pct: 3.0,
      attack_target_pct: 2.0,
      recorded_at: @now
    )
  end

  test "latest_batch returns snapshots from most recent recorded_at" do
    old = InternetTrafficSnapshot.create!(
      country_code: "FR",
      country_name: "France",
      traffic_pct: 5.0,
      recorded_at: 1.hour.ago
    )

    batch = InternetTrafficSnapshot.latest_batch
    assert_includes batch, @snap1
    assert_includes batch, @snap2
    assert_not_includes batch, old
  end

  test "latest_batch returns none when table is empty" do
    InternetTrafficSnapshot.delete_all
    assert_equal 0, InternetTrafficSnapshot.latest_batch.count
  end

  test "required columns" do
    snap = InternetTrafficSnapshot.new(country_code: "JP", recorded_at: Time.current)
    assert snap.save
  end
end
