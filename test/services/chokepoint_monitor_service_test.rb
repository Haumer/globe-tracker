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
end
