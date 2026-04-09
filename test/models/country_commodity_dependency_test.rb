require "test_helper"

class CountryCommodityDependencyTest < ActiveSupport::TestCase
  test "valid creation" do
    record = CountryCommodityDependency.create!(
      country_code_alpha3: "DEU",
      country_name: "Germany",
      commodity_key: "natural_gas"
    )
    assert record.persisted?
  end

  test "country_code_alpha3 is required" do
    r = CountryCommodityDependency.new(country_name: "Germany", commodity_key: "gas")
    assert_not r.valid?
    assert_includes r.errors[:country_code_alpha3], "can't be blank"
  end

  test "country_name is required" do
    r = CountryCommodityDependency.new(country_code_alpha3: "DEU", commodity_key: "gas")
    assert_not r.valid?
    assert_includes r.errors[:country_name], "can't be blank"
  end

  test "commodity_key is required" do
    r = CountryCommodityDependency.new(country_code_alpha3: "DEU", country_name: "Germany")
    assert_not r.valid?
    assert_includes r.errors[:commodity_key], "can't be blank"
  end
end
