require "test_helper"

class TrainObservationTest < ActiveSupport::TestCase
  setup do
    @obs = TrainObservation.create!(
      external_id: "train-001",
      source: "hafas",
      latitude: 52.52,
      longitude: 13.405,
      fetched_at: Time.current,
      expires_at: 5.minutes.from_now
    )
  end

  test "valid creation" do
    assert @obs.persisted?
  end

  test "external_id is required" do
    r = TrainObservation.new(fetched_at: Time.current)
    assert_not r.valid?
    assert_includes r.errors[:external_id], "can't be blank"
  end

  test "external_id is unique" do
    dup = TrainObservation.new(external_id: "train-001", fetched_at: Time.current)
    assert_not dup.valid?
    assert dup.errors[:external_id].any?
  end

  test "fetched_at is required" do
    r = TrainObservation.new(external_id: "train-002")
    assert_not r.valid?
    assert_includes r.errors[:fetched_at], "can't be blank"
  end

  test "train_ingest is optional" do
    assert_nil @obs.train_ingest
  end

  test "matched_railway is optional" do
    assert_nil @obs.matched_railway
  end

  test "current scope returns non-expired observations" do
    expired = TrainObservation.create!(
      external_id: "train-old", fetched_at: 10.minutes.ago, expires_at: 5.minutes.ago
    )
    results = TrainObservation.current
    assert_includes results, @obs
    assert_not_includes results, expired
  end

  test "within_bounds from BoundsFilterable" do
    results = TrainObservation.within_bounds(lamin: 52.0, lamax: 53.0, lomin: 13.0, lomax: 14.0)
    assert_includes results, @obs

    results = TrainObservation.within_bounds(lamin: 40.0, lamax: 41.0, lomin: 0.0, lomax: 1.0)
    assert_not_includes results, @obs
  end
end
