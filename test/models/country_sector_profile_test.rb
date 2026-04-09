require "test_helper"

class CountrySectorProfileTest < ActiveSupport::TestCase
  test "valid creation" do
    record = CountrySectorProfile.create!(
      country_code_alpha3: "USA", country_name: "United States",
      sector_key: "agriculture", sector_name: "Agriculture", period_year: 2024
    )
    assert record.persisted?
  end

  test "country_code_alpha3 is required" do
    r = CountrySectorProfile.new(country_name: "US", sector_key: "ag", sector_name: "Ag", period_year: 2024)
    assert_not r.valid?
    assert_includes r.errors[:country_code_alpha3], "can't be blank"
  end

  test "sector_key is required" do
    r = CountrySectorProfile.new(country_code_alpha3: "USA", country_name: "US", sector_name: "Ag", period_year: 2024)
    assert_not r.valid?
    assert_includes r.errors[:sector_key], "can't be blank"
  end

  test "period_year is required" do
    r = CountrySectorProfile.new(country_code_alpha3: "USA", country_name: "US", sector_key: "ag", sector_name: "Ag")
    assert_not r.valid?
    assert_includes r.errors[:period_year], "can't be blank"
  end
end
