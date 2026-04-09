require "test_helper"

class TradeLocationTest < ActiveSupport::TestCase
  setup do
    @location = TradeLocation.create!(
      locode: "USNYC",
      name: "New York",
      location_kind: "trade_node",
      status: "active",
      source: "unece"
    )
  end

  test "valid creation" do
    assert @location.persisted?
  end

  test "locode is required" do
    r = TradeLocation.new(name: "Test", source: "unece")
    assert_not r.valid?
    assert_includes r.errors[:locode], "can't be blank"
  end

  test "name is required" do
    r = TradeLocation.new(locode: "XXYYY", source: "unece")
    assert_not r.valid?
    assert_includes r.errors[:name], "can't be blank"
  end

  test "source is required" do
    r = TradeLocation.new(locode: "XXYYY", name: "Test")
    assert_not r.valid?
    assert_includes r.errors[:source], "can't be blank"
  end

  test "location_kind is required" do
    r = TradeLocation.new(locode: "XXYYY", name: "Test", source: "unece")
    r.location_kind = nil
    assert_not r.valid?
    assert_includes r.errors[:location_kind], "can't be blank"
  end

  test "status is required" do
    r = TradeLocation.new(locode: "XXYYY", name: "Test", source: "unece")
    r.status = nil
    assert_not r.valid?
    assert_includes r.errors[:status], "can't be blank"
  end

  test "active scope returns active locations" do
    inactive = TradeLocation.create!(locode: "DEBER", name: "Berlin", source: "unece", status: "inactive")
    results = TradeLocation.active
    assert_includes results, @location
    assert_not_includes results, inactive
  end
end
