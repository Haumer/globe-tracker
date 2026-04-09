require "test_helper"

class EnergyBalanceSnapshotTest < ActiveSupport::TestCase
  test "valid creation" do
    record = EnergyBalanceSnapshot.create!(
      country_code_alpha3: "DEU", country_name: "Germany",
      commodity_key: "natural_gas", metric_key: "production",
      period_type: "month", period_start: Date.new(2024, 1, 1),
      source: "iea", dataset: "monthly_gas"
    )
    assert record.persisted?
  end

  test "commodity_key is required" do
    r = EnergyBalanceSnapshot.new(
      country_code_alpha3: "DEU", country_name: "Germany",
      metric_key: "production", period_start: Date.today, source: "iea", dataset: "mg"
    )
    assert_not r.valid?
    assert_includes r.errors[:commodity_key], "can't be blank"
  end

  test "metric_key is required" do
    r = EnergyBalanceSnapshot.new(
      country_code_alpha3: "DEU", country_name: "Germany",
      commodity_key: "gas", period_start: Date.today, source: "iea", dataset: "mg"
    )
    assert_not r.valid?
    assert_includes r.errors[:metric_key], "can't be blank"
  end

  test "latest_first scope orders by period_start desc" do
    old = EnergyBalanceSnapshot.create!(
      country_code_alpha3: "DEU", country_name: "Germany",
      commodity_key: "gas", metric_key: "prod",
      period_start: Date.new(2020, 1, 1), source: "iea", dataset: "mg"
    )
    recent = EnergyBalanceSnapshot.create!(
      country_code_alpha3: "DEU", country_name: "Germany",
      commodity_key: "gas", metric_key: "imports",
      period_start: Date.new(2024, 6, 1), source: "iea", dataset: "mg"
    )
    results = EnergyBalanceSnapshot.latest_first
    assert_operator results.index(recent), :<, results.index(old)
  end
end
