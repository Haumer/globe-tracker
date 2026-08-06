require "test_helper"

class DataRetentionTest < ActiveSupport::TestCase
  test "defaults to a two week window" do
    assert_equal 14, DataRetention.days
    assert_equal 14.days, DataRetention.window
  end

  test "cutoff is the window behind the supplied clock" do
    now = Time.utc(2026, 8, 6, 12, 0, 0)

    assert_equal now - 14.days, DataRetention.cutoff(now: now)
  end

  test "honours DATA_RETENTION_DAYS" do
    with_env("DATA_RETENTION_DAYS", "30") do
      assert_equal 30, DataRetention.days
    end
  end

  test "clamps absurd overrides instead of trusting them" do
    with_env("DATA_RETENTION_DAYS", "0") { assert_equal DataRetention::MIN_DAYS, DataRetention.days }
    with_env("DATA_RETENTION_DAYS", "9999") { assert_equal DataRetention::MAX_DAYS, DataRetention.days }
  end

  private

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = original
  end
end
