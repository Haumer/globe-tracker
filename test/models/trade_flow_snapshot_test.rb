require "test_helper"

class TradeFlowSnapshotTest < ActiveSupport::TestCase
  test "valid creation" do
    record = TradeFlowSnapshot.create!(
      reporter_country_code_alpha3: "USA",
      partner_country_code_alpha3: "CHN",
      flow_direction: "import",
      commodity_key: "electronics",
      period_type: "month",
      period_start: Date.new(2024, 1, 1),
      source: "comtrade",
      dataset: "hs6"
    )
    assert record.persisted?
  end

  test "reporter_country_code_alpha3 is required" do
    r = TradeFlowSnapshot.new(partner_country_code_alpha3: "CHN", flow_direction: "import", commodity_key: "x", period_start: Date.today, source: "x", dataset: "x")
    assert_not r.valid?
    assert_includes r.errors[:reporter_country_code_alpha3], "can't be blank"
  end

  test "flow_direction is required" do
    r = TradeFlowSnapshot.new(reporter_country_code_alpha3: "USA", partner_country_code_alpha3: "CHN", commodity_key: "x", period_start: Date.today, source: "x", dataset: "x")
    assert_not r.valid?
    assert_includes r.errors[:flow_direction], "can't be blank"
  end

  test "commodity_key is required" do
    r = TradeFlowSnapshot.new(reporter_country_code_alpha3: "USA", partner_country_code_alpha3: "CHN", flow_direction: "import", period_start: Date.today, source: "x", dataset: "x")
    assert_not r.valid?
    assert_includes r.errors[:commodity_key], "can't be blank"
  end

  test "latest_first scope orders by period_start desc" do
    old = TradeFlowSnapshot.create!(
      reporter_country_code_alpha3: "USA", partner_country_code_alpha3: "CHN",
      flow_direction: "import", commodity_key: "oil",
      period_start: Date.new(2020, 1, 1), source: "ct", dataset: "hs6"
    )
    recent = TradeFlowSnapshot.create!(
      reporter_country_code_alpha3: "USA", partner_country_code_alpha3: "CHN",
      flow_direction: "import", commodity_key: "gas",
      period_start: Date.new(2024, 6, 1), source: "ct", dataset: "hs6"
    )
    results = TradeFlowSnapshot.latest_first
    assert_operator results.index(recent), :<, results.index(old)
  end
end
