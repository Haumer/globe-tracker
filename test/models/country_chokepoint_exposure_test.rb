require "test_helper"

class CountryChokepointExposureTest < ActiveSupport::TestCase
  test "valid creation" do
    record = CountryChokepointExposure.create!(
      country_code_alpha3: "USA",
      country_name: "United States",
      commodity_key: "crude_oil",
      chokepoint_key: "strait_hormuz",
      chokepoint_name: "Strait of Hormuz"
    )
    assert record.persisted?
  end

  test "country_code_alpha3 is required" do
    r = CountryChokepointExposure.new(country_name: "US", commodity_key: "oil", chokepoint_key: "x", chokepoint_name: "X")
    assert_not r.valid?
    assert_includes r.errors[:country_code_alpha3], "can't be blank"
  end

  test "country_name is required" do
    r = CountryChokepointExposure.new(country_code_alpha3: "USA", commodity_key: "oil", chokepoint_key: "x", chokepoint_name: "X")
    assert_not r.valid?
    assert_includes r.errors[:country_name], "can't be blank"
  end

  test "commodity_key is required" do
    r = CountryChokepointExposure.new(country_code_alpha3: "USA", country_name: "US", chokepoint_key: "x", chokepoint_name: "X")
    assert_not r.valid?
    assert_includes r.errors[:commodity_key], "can't be blank"
  end

  test "chokepoint_key is required" do
    r = CountryChokepointExposure.new(country_code_alpha3: "USA", country_name: "US", commodity_key: "oil", chokepoint_name: "X")
    assert_not r.valid?
    assert_includes r.errors[:chokepoint_key], "can't be blank"
  end

  test "chokepoint_name is required" do
    r = CountryChokepointExposure.new(country_code_alpha3: "USA", country_name: "US", commodity_key: "oil", chokepoint_key: "x")
    assert_not r.valid?
    assert_includes r.errors[:chokepoint_name], "can't be blank"
  end
end
