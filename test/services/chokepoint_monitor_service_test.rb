require "test_helper"

class ChokepointMonitorServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "CHOKEPOINTS contains major shipping lanes" do
    assert ChokepointMonitorService::CHOKEPOINTS.key?(:hormuz)
    assert ChokepointMonitorService::CHOKEPOINTS.key?(:suez)
    assert ChokepointMonitorService::CHOKEPOINTS.key?(:malacca)
    assert ChokepointMonitorService::CHOKEPOINTS.key?(:taiwan_strait)
  end

  test "each chokepoint has required fields" do
    ChokepointMonitorService::CHOKEPOINTS.each do |key, cp|
      assert cp[:name].present?, "#{key} missing name"
      assert cp[:lat].present?, "#{key} missing lat"
      assert cp[:lng].present?, "#{key} missing lng"
      assert cp[:radius_km].present?, "#{key} missing radius_km"
      assert cp[:flows].present?, "#{key} missing flows"
      assert cp[:countries].is_a?(Array), "#{key} countries not array"
    end
  end

  test "analyze returns all chokepoints with status" do
    results = ChokepointMonitorService.analyze
    assert_equal ChokepointMonitorService::CHOKEPOINTS.size, results.size

    results.each do |cp|
      assert cp[:name].present?
      assert %w[normal monitoring elevated critical].include?(cp[:status])
      assert cp[:ships_nearby].is_a?(Hash)
      assert cp[:checked_at].present?
    end
  end

  test "analyze includes commodity signals when recent quotes exist" do
    CommodityPrice.create!(
      symbol: "OIL_BRENT",
      category: "commodity",
      name: "Brent Crude",
      price: 87.4,
      change_pct: 2.1,
      unit: "USD/bbl",
      latitude: 26.56,
      longitude: 56.27,
      region: "Middle East",
      recorded_at: Time.current
    )

    hormuz = ChokepointMonitorService.analyze.find { |cp| cp[:id] == "hormuz" }
    signal = hormuz[:commodity_signals].find { |entry| entry[:symbol] == "OIL_BRENT" }

    assert signal
    assert_equal "Brent Crude", signal[:name]
    assert_equal 2.1, signal[:change_pct]
  end

  test "determine_status returns elevated when conflict pulse present" do
    conflict_zones = [{ score: 60, trend: "escalating" }]
    status = ChokepointMonitorService.send(:determine_status, { total: 10 }, conflict_zones, {})
    assert_equal "elevated", status
  end

  test "determine_status returns critical for high conflict pulse" do
    conflict_zones = [{ score: 75, trend: "surging" }]
    status = ChokepointMonitorService.send(:determine_status, { total: 10 }, conflict_zones, {})
    assert_equal "critical", status
  end

  test "determine_status returns normal with no conflict" do
    status = ChokepointMonitorService.send(:determine_status, { total: 50 }, [], {})
    assert_equal "normal", status
  end

  test "count_ships_near finds ships within radius" do
    Ship.create!(
      mmsi: "test-ship-choke", name: "Test Vessel",
      latitude: 55.7, longitude: 12.6,
      speed: 8, heading: 90,
    )

    result = ChokepointMonitorService.send(:count_ships_near, 55.7, 12.6, 30)
    assert_operator result[:total], :>=, 1
  end

  test "count_ships_near classifies cargo and tankers using AIS ship type codes" do
    Ship.create!(
      mmsi: "test-ship-cargo", name: "Cargo Vessel",
      ship_type: 70,
      latitude: 55.7, longitude: 12.6,
      speed: 8, heading: 90,
    )
    Ship.create!(
      mmsi: "test-ship-tanker", name: "Tanker Vessel",
      ship_type: 80,
      latitude: 55.71, longitude: 12.61,
      speed: 9, heading: 95,
    )

    result = ChokepointMonitorService.send(:count_ships_near, 55.7, 12.6, 30)

    assert_operator result[:cargo], :>=, 1
    assert_operator result[:tankers], :>=, 1
  end

  test "nearby conflict pulse keeps theater metadata" do
    conflict_pulse_singleton = class << ConflictPulseService; self; end
    original_analyze = ConflictPulseService.method(:analyze)

    conflict_pulse_singleton.send(:define_method, :analyze) do
      {
        zones: [
          {
            lat: 26.7,
            lng: 56.3,
            pulse_score: 78,
            escalation_trend: "active",
            theater: "Middle East / Iran War",
            top_headlines: ["Shipping pressure builds around Hormuz"],
          },
        ],
      }
    end

    begin
      result = ChokepointMonitorService.send(:nearby_conflict_pulse, 26.56, 56.27)
      assert_equal "Middle East / Iran War", result.dig(0, :theater)
      assert_equal "Shipping pressure builds around Hormuz", result.dig(0, :headline)
    ensure
      conflict_pulse_singleton.send(:define_method, :analyze, original_analyze)
    end
  end
end
