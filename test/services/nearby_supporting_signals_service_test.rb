require "test_helper"

class NearbySupportingSignalsServiceTest < ActiveSupport::TestCase
  test "builds strike supporting signals for supported nearby scopes" do
    FireHotspot.create!(
      external_id: "svc-strike-near-001",
      latitude: 26.7,
      longitude: 56.45,
      brightness: 348.0,
      confidence: "high",
      satellite: "Aqua",
      instrument: "MODIS",
      frp: 58.2,
      daynight: "N",
      acq_datetime: 18.hours.ago,
      fetched_at: Time.current
    )
    FireHotspot.create!(
      external_id: "svc-strike-old-001",
      latitude: 26.65,
      longitude: 56.33,
      brightness: 342.0,
      confidence: "high",
      satellite: "Terra",
      instrument: "MODIS",
      frp: 42.0,
      daynight: "D",
      acq_datetime: 9.days.ago,
      fetched_at: Time.current
    )

    signals = NearbySupportingSignalsService.call(
      object_kind: "theater",
      latitude: 26.55,
      longitude: 56.3
    )

    assert signals.present?
    assert_equal "7-day nearby scope", signals[:scope_label]
    assert_equal 1, signals[:groups].size
    group = signals[:groups].first
    assert_equal "Strike Signals", group[:title]
    assert_equal 1, group[:metrics].first[:value]
    assert_equal "Thermal strike signal", group[:items].first[:title]
    assert_includes group[:items].first[:meta], "Aqua"
  end

  test "returns nil for unsupported kinds" do
    signals = NearbySupportingSignalsService.call(
      object_kind: "news_story_cluster",
      latitude: 26.55,
      longitude: 56.3
    )

    assert_nil signals
  end

  test "builds canonical cross layer signal keys" do
    FireHotspot.create!(
      external_id: "svc-strike-near-002",
      latitude: 26.7,
      longitude: 56.45,
      brightness: 348.0,
      confidence: "high",
      satellite: "Aqua",
      instrument: "MODIS",
      frp: 58.2,
      daynight: "N",
      acq_datetime: 18.hours.ago,
      fetched_at: Time.current
    )

    signals = NearbySupportingSignalsService.cross_layer_signals(
      object_kind: "chokepoint",
      latitude: 26.55,
      longitude: 56.3
    )

    assert_equal 1, signals[:strike_signals_7d]
    assert_nil signals[:verified_strike_reports_7d]
  end
end
