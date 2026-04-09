require "test_helper"

class TimeRangeQueriesTest < ActiveSupport::TestCase
  setup do
    Earthquake.where(external_id: %w[tr-recent tr-old tr-date]).delete_all

    @recent = Earthquake.create!(
      external_id: "tr-recent",
      title: "Recent quake",
      magnitude: 3.0,
      latitude: 40.0, longitude: -100.0, depth: 5.0,
      event_time: 2.hours.ago,
      fetched_at: Time.current,
    )
    @old = Earthquake.create!(
      external_id: "tr-old",
      title: "Old quake",
      magnitude: 3.0,
      latitude: 40.0, longitude: -100.0, depth: 5.0,
      event_time: 3.days.ago,
      fetched_at: Time.current,
    )
  end

  test "recent scope returns only records within configured window" do
    results = Earthquake.recent
    assert_includes results, @recent
    assert_not_includes results, @old
  end

  test "in_range scope returns records within specified range" do
    results = Earthquake.in_range(4.days.ago, 1.day.ago)
    assert_includes results, @old
    assert_not_includes results, @recent

    results = Earthquake.in_range(4.days.ago, Time.current)
    assert_includes results, @old
    assert_includes results, @recent
  end

  test "on_date scope returns records for specific date" do
    results = Earthquake.on_date(Date.current)
    assert_includes results, @recent
    assert_not_includes results, @old

    results = Earthquake.on_date(3.days.ago.to_date)
    assert_includes results, @old
    assert_not_includes results, @recent
  end
end
