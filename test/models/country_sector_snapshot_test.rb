require "test_helper"

class CountrySectorSnapshotTest < ActiveSupport::TestCase
  test "valid creation" do
    record = CountrySectorSnapshot.create!(
      country_code_alpha3: "USA", country_name: "United States",
      sector_key: "energy", sector_name: "Energy",
      metric_key: "output", metric_name: "Output",
      period_year: 2024, source: "worldbank", dataset: "wdi"
    )
    assert record.persisted?
  end

  test "metric_key is required" do
    r = CountrySectorSnapshot.new(
      country_code_alpha3: "USA", country_name: "US",
      sector_key: "e", sector_name: "E", metric_name: "O",
      period_year: 2024, source: "wb", dataset: "wdi"
    )
    assert_not r.valid?
    assert_includes r.errors[:metric_key], "can't be blank"
  end

  test "source is required" do
    r = CountrySectorSnapshot.new(
      country_code_alpha3: "USA", country_name: "US",
      sector_key: "e", sector_name: "E", metric_key: "o", metric_name: "O",
      period_year: 2024, dataset: "wdi"
    )
    assert_not r.valid?
    assert_includes r.errors[:source], "can't be blank"
  end

  test "latest_first scope orders by period_year desc" do
    old = CountrySectorSnapshot.create!(
      country_code_alpha3: "USA", country_name: "US",
      sector_key: "energy", sector_name: "Energy",
      metric_key: "output", metric_name: "Output",
      period_year: 2020, source: "wb", dataset: "wdi"
    )
    recent = CountrySectorSnapshot.create!(
      country_code_alpha3: "USA", country_name: "US",
      sector_key: "energy", sector_name: "Energy",
      metric_key: "employment", metric_name: "Employment",
      period_year: 2024, source: "wb", dataset: "wdi"
    )
    results = CountrySectorSnapshot.latest_first
    assert_operator results.index(recent), :<, results.index(old)
  end
end
