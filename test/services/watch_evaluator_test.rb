require "test_helper"

class WatchEvaluatorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "watch-eval@example.com", password: "password123")
  end

  test "evaluate area watch with flights in bounds" do
    Flight.create!(
      icao24: "we-f1", callsign: "TEST01",
      latitude: 48.2, longitude: 16.3, altitude: 35000,
      origin_country: "Austria", military: false
    )

    watch = Watch.create!(
      user: @user, name: "Vienna Area", watch_type: "area",
      conditions: { bounds: [47.0, 15.0, 49.0, 17.0], entity_types: ["flight"] },
      cooldown_minutes: 1
    )

    alerts = WatchEvaluator.evaluate(@user)
    assert_equal 1, alerts.size
    assert_includes alerts.first.title, "flight"
  end

  test "evaluate area watch with no matching entities" do
    watch = Watch.create!(
      user: @user, name: "Empty Area", watch_type: "area",
      conditions: { bounds: [0.0, 0.0, 1.0, 1.0], entity_types: ["flight"] },
      cooldown_minutes: 1
    )

    alerts = WatchEvaluator.evaluate(@user)
    assert_empty alerts
  end

  test "evaluate entity watch finds matching flight" do
    Flight.create!(
      icao24: "we-f2", callsign: "AUA123",
      latitude: 48.2, longitude: 16.3, altitude: 35000,
      origin_country: "Austria", military: false
    )

    watch = Watch.create!(
      user: @user, name: "Track AUA", watch_type: "entity",
      conditions: { entity_type: "flight", identifier: "AUA*", match: "callsign_glob" },
      cooldown_minutes: 1
    )

    alerts = WatchEvaluator.evaluate(@user)
    assert_equal 1, alerts.size
    assert_includes alerts.first.title, "AUA123"
  end

  test "cooldown prevents duplicate alerts" do
    Flight.create!(
      icao24: "we-f3", callsign: "COOL01",
      latitude: 48.2, longitude: 16.3, altitude: 35000,
      origin_country: "Austria", military: false
    )

    watch = Watch.create!(
      user: @user, name: "Cooldown Test", watch_type: "entity",
      conditions: { entity_type: "flight", identifier: "COOL01", match: "callsign_exact" },
      cooldown_minutes: 60
    )

    # First evaluation creates alert
    alerts1 = WatchEvaluator.evaluate(@user)
    assert_equal 1, alerts1.size

    # Second evaluation within cooldown creates no new alert
    alerts2 = WatchEvaluator.evaluate(@user)
    assert_empty alerts2
  end

  test "inactive watches are skipped" do
    watch = Watch.create!(
      user: @user, name: "Inactive", watch_type: "area",
      conditions: { bounds: [47.0, 15.0, 49.0, 17.0], entity_types: ["flight"] },
      active: false, cooldown_minutes: 1
    )
    Flight.create!(icao24: "we-f4", callsign: "SKIP", latitude: 48.0, longitude: 16.0, altitude: 30000, origin_country: "AT", military: false)

    alerts = WatchEvaluator.evaluate(@user)
    assert_empty alerts
  end
end
