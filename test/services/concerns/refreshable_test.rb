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

  # A model with more than one writer: reading the whole table answers "did
  # anyone write recently", not "did this service run recently", so a busy
  # sibling pins this service to not-stale forever. Sitemap starved GDELT this
  # way for a full hour.
  class ScopedFakeModel
    def self.maximum(_col)
      @all_max
    end

    def self.set_all_max(val)
      @all_max = val
    end

    def self.own_rows
      @own_rows ||= Object.new.tap do |o|
        def o.maximum(_col) = @own_max
        def o.set_own_max(val) = @own_max = val
      end
    end
  end

  class ScopedService
    extend Refreshable
    refreshes model: RefreshableTest::ScopedFakeModel,
              interval: 5.minutes,
              scope: -> { RefreshableTest::ScopedFakeModel.own_rows }
  end

  test "a scoped service ignores rows written by other services" do
    ScopedFakeModel.set_all_max(Time.current)          # sibling just wrote
    ScopedFakeModel.own_rows.set_own_max(1.hour.ago)   # this service has not run

    assert_equal 1, [ScopedService.latest_fetch_at].compact.size
    assert ScopedService.stale?,
      "a sibling's fresh rows must not mask this service being overdue"
  end

  test "a scoped service is not stale when its own rows are fresh" do
    ScopedFakeModel.set_all_max(1.hour.ago)
    ScopedFakeModel.own_rows.set_own_max(1.minute.ago)

    assert_not ScopedService.stale?
  end
end
