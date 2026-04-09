require "test_helper"

class CountryIndicatorSnapshotTest < ActiveSupport::TestCase
  test "valid creation" do
    record = CountryIndicatorSnapshot.create!(
      country_code_alpha3: "USA",
      country_name: "United States",
      indicator_key: "gdp_growth",
      indicator_name: "GDP Growth",
      period_type: "year",
      period_start: Date.new(2024, 1, 1),
      source: "worldbank",
      dataset: "wdi"
    )
    assert record.persisted?
  end

  test "country_code_alpha3 is required" do
    r = CountryIndicatorSnapshot.new(country_name: "US", indicator_key: "x", indicator_name: "X", period_start: Date.today, source: "wb", dataset: "wdi")
    assert_not r.valid?
    assert_includes r.errors[:country_code_alpha3], "can't be blank"
  end

  test "indicator_key is required" do
    r = CountryIndicatorSnapshot.new(country_code_alpha3: "USA", country_name: "US", indicator_name: "X", period_start: Date.today, source: "wb", dataset: "wdi")
    assert_not r.valid?
    assert_includes r.errors[:indicator_key], "can't be blank"
  end

  test "source is required" do
    r = CountryIndicatorSnapshot.new(country_code_alpha3: "USA", country_name: "US", indicator_key: "x", indicator_name: "X", period_start: Date.today, dataset: "wdi")
    assert_not r.valid?
    assert_includes r.errors[:source], "can't be blank"
  end

  test "dataset is required" do
    r = CountryIndicatorSnapshot.new(country_code_alpha3: "USA", country_name: "US", indicator_key: "x", indicator_name: "X", period_start: Date.today, source: "wb")
    assert_not r.valid?
    assert_includes r.errors[:dataset], "can't be blank"
  end

  test "latest_first scope orders by period_start desc" do
    old = CountryIndicatorSnapshot.create!(
      country_code_alpha3: "USA", country_name: "US", indicator_key: "gdp",
      indicator_name: "GDP", period_start: Date.new(2020, 1, 1), source: "wb", dataset: "wdi"
    )
    recent = CountryIndicatorSnapshot.create!(
      country_code_alpha3: "USA", country_name: "US", indicator_key: "inflation",
      indicator_name: "Inflation", period_start: Date.new(2024, 1, 1), source: "wb", dataset: "wdi"
    )
    results = CountryIndicatorSnapshot.latest_first
    assert_operator results.index(recent), :<, results.index(old)
  end
end
