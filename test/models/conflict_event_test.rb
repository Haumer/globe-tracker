require "test_helper"

class ConflictEventTest < ActiveSupport::TestCase
  setup do
    @conflict = ConflictEvent.create!(
      external_id: 12345,
      conflict_name: "War in Donbas",
      country: "Ukraine",
      where_description: "Bakhmut",
      latitude: 48.59,
      longitude: 37.99,
      date_start: 1.month.ago.to_date,
      date_end: 2.weeks.ago.to_date,
      best_estimate: 15,
      type_of_violence: 1,
      source_headline: "Reuters",
    )
  end

  test "violence_label returns correct labels" do
    @conflict.type_of_violence = 1
    assert_equal "State-based", @conflict.violence_label

    @conflict.type_of_violence = 2
    assert_equal "Non-state", @conflict.violence_label

    @conflict.type_of_violence = 3
    assert_equal "One-sided", @conflict.violence_label

    @conflict.type_of_violence = 99
    assert_equal "Unknown", @conflict.violence_label
  end

  test "within_bounds filters correctly" do
    inside = ConflictEvent.within_bounds(lamin: 48.0, lamax: 49.0, lomin: 37.0, lomax: 39.0)
    assert_includes inside, @conflict

    outside = ConflictEvent.within_bounds(lamin: 0.0, lamax: 1.0, lomin: 0.0, lomax: 1.0)
    assert_not_includes outside, @conflict
  end

  test "recent scope returns events within 1 year" do
    old = ConflictEvent.create!(
      external_id: 99999,
      country: "Syria",
      latitude: 35.0, longitude: 38.0,
      date_start: 2.years.ago.to_date,
      best_estimate: 5,
      type_of_violence: 1,
    )

    recent = ConflictEvent.recent
    assert_includes recent, @conflict
    assert_not_includes recent, old
  end
end
