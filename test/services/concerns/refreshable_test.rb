require "test_helper"

class RefreshableTest < ActiveSupport::TestCase
  class FakeRefreshModel
    def self.maximum(col)
      @max_val
    end

    def self.set_max(val)
      @max_val = val
    end
  end

  class FakeService
    extend Refreshable
    refreshes model: RefreshableTest::FakeRefreshModel, interval: 5.minutes, column: :fetched_at

    def refresh
      42
    end
  end

  test "stale? returns true when no records exist" do
    FakeRefreshModel.set_max(nil)
    assert FakeService.stale?
  end

  test "stale? returns false when data is fresh" do
    FakeRefreshModel.set_max(1.minute.ago)
    assert_not FakeService.stale?
  end

  test "stale? returns true when data is old" do
    FakeRefreshModel.set_max(10.minutes.ago)
    assert FakeService.stale?
  end

  test "refresh_if_stale returns 0 when not stale and not forced" do
    FakeRefreshModel.set_max(1.minute.ago)
    assert_equal 0, FakeService.refresh_if_stale
  end

  test "latest_fetch_at delegates to model" do
    FakeRefreshModel.set_max(Time.current)
    assert_not_nil FakeService.latest_fetch_at
  end
end
