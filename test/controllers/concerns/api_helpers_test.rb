require "test_helper"

class ApiHelpersTest < ActionDispatch::IntegrationTest
  # Test via the earthquakes endpoint which uses ApiHelpers (included in ApplicationController)

  setup do
    @eq = Earthquake.create!(
      external_id: "us-apihelper-001",
      title: "ApiHelper Test Quake",
      magnitude: 3.0,
      latitude: 40.0,
      longitude: -100.0,
      depth: 5.0,
      event_time: 2.hours.ago,
      fetched_at: Time.current,
    )
  end

  test "parse_time_range filters via from/to params" do
    old_eq = Earthquake.create!(
      external_id: "us-apihelper-old",
      title: "Old Quake",
      magnitude: 2.0,
      latitude: 40.0, longitude: -100.0, depth: 5.0,
      event_time: 5.days.ago,
      fetched_at: Time.current,
    )

    # Default (recent 24h) should exclude old
    get "/api/earthquakes"
    data = JSON.parse(response.body)
    ids = data.map { |e| e["id"] }
    assert_not_includes ids, "us-apihelper-old"

    # Explicit time range should include old
    get "/api/earthquakes", params: { from: 6.days.ago.iso8601, to: Time.current.iso8601 }
    data = JSON.parse(response.body)
    ids = data.map { |e| e["id"] }
    assert_includes ids, "us-apihelper-old"
  end

  test "parse_json_field handles various inputs" do
    # Test via a controller that uses parse_json_field indirectly.
    # We test the module directly here.
    controller = Class.new(ActionController::Base) { include ApiHelpers }.new

    assert_equal [1, 2], controller.send(:parse_json_field, [1, 2])
    assert_equal [], controller.send(:parse_json_field, nil)
    assert_equal [], controller.send(:parse_json_field, "")
    assert_equal [1, 2], controller.send(:parse_json_field, "[1,2]")
  end

  test "safe_thread_value returns thread value on success" do
    controller = Class.new(ActionController::Base) { include ApiHelpers }.new
    thread = Thread.new { 42 }
    thread.join
    assert_equal 42, controller.send(:safe_thread_value, thread, "test")
  end

  test "safe_thread_value returns fallback on error" do
    controller = Class.new(ActionController::Base) { include ApiHelpers }.new
    thread = Thread.new { raise "boom" }
    thread.join rescue nil
    assert_equal [], controller.send(:safe_thread_value, thread, "test")
  end
end
