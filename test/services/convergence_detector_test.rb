require "test_helper"

class ConvergenceDetectorTest < ActiveSupport::TestCase
  test "detect with multi-layer data in same cell returns convergence" do
    # Place earthquake and fire in same 2-degree cell (both have proper timestamps)
    Earthquake.create!(
      external_id: "conv-eq-1", title: "M6.0 test",
      magnitude: 6.0, latitude: 35.0, longitude: 45.0, depth: 10,
      event_time: 6.hours.ago, fetched_at: Time.current
    )
    6.times do |i|
      FireHotspot.create!(
        external_id: "conv-fire-#{i}", latitude: 35.5, longitude: 45.5,
        brightness: 350, confidence: "high", frp: 50.0,
        acq_datetime: 6.hours.ago
      )
    end

    insights = ConvergenceDetector.new.detect

    convergences = insights.select { |i| i[:type] == "convergence" }
    assert convergences.any?, "Expected at least one convergence insight"
    assert convergences.first[:layer_count] >= 2
  end

  test "detect with no data returns empty array" do
    insights = ConvergenceDetector.new.detect
    assert_equal [], insights
  end

  test "detect with single layer returns empty" do
    Earthquake.create!(
      external_id: "conv-eq-solo", title: "Solo quake",
      magnitude: 5.0, latitude: -40.0, longitude: 170.0, depth: 20,
      event_time: 3.hours.ago, fetched_at: Time.current
    )

    insights = ConvergenceDetector.new.detect
    assert_empty insights
  end
end
