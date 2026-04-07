require "test_helper"

class InternetAttackPairSnapshotTest < ActiveSupport::TestCase
  test "latest_batch returns rows from most recent recorded_at" do
    latest = Time.current
    old = 2.hours.ago

    old_pair = InternetAttackPairSnapshot.create!(
      origin_country_code: "US",
      target_country_code: "DE",
      attack_pct: 4.2,
      recorded_at: old
    )
    latest_pair = InternetAttackPairSnapshot.create!(
      origin_country_code: "FR",
      target_country_code: "ES",
      attack_pct: 7.1,
      recorded_at: latest
    )

    batch = InternetAttackPairSnapshot.latest_batch
    assert_includes batch, latest_pair
    assert_not_includes batch, old_pair
  end

  test "latest_batch_at returns latest rows at or before timestamp" do
    early = 3.hours.ago
    late = 1.hour.ago

    early_pair = InternetAttackPairSnapshot.create!(
      origin_country_code: "US",
      target_country_code: "DE",
      attack_pct: 4.2,
      recorded_at: early
    )
    InternetAttackPairSnapshot.create!(
      origin_country_code: "US",
      target_country_code: "FR",
      attack_pct: 8.5,
      recorded_at: late
    )

    batch = InternetAttackPairSnapshot.latest_batch_at(2.hours.ago)
    assert_equal [early_pair], batch.to_a
  end
end
