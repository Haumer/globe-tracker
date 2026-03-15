require "test_helper"

class InternetOutageTest < ActiveSupport::TestCase
  setup do
    @outage = InternetOutage.create!(
      external_id: "OUTAGE-TEST-001",
      entity_type: "country",
      entity_code: "SY",
      entity_name: "Syria",
      datasource: "ioda",
      score: 85.0,
      level: "critical",
      condition: "ongoing",
      started_at: 2.hours.ago,
      fetched_at: Time.current,
    )
  end

  test "basic creation with all fields" do
    assert_equal "Syria", @outage.entity_name
    assert_equal "critical", @outage.level
    assert_equal "country", @outage.entity_type
  end

  test "recent scope returns outages from last 24 hours" do
    old = InternetOutage.create!(
      external_id: "OUTAGE-TEST-002",
      entity_type: "country",
      entity_code: "IR",
      entity_name: "Iran",
      started_at: 3.days.ago,
      fetched_at: Time.current,
    )

    assert_includes InternetOutage.recent, @outage
    assert_not_includes InternetOutage.recent, old
  end

  test "in_range scope filters by started_at" do
    results = InternetOutage.in_range(6.hours.ago, Time.current)
    assert_includes results, @outage

    results = InternetOutage.in_range(1.week.ago, 1.day.ago)
    assert_not_includes results, @outage
  end

  test "unique external_id constraint" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      InternetOutage.create!(
        external_id: "OUTAGE-TEST-001",
        entity_type: "country",
        entity_code: "SY",
        started_at: 1.hour.ago,
        fetched_at: Time.current,
      )
    end
  end
end
