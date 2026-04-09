require "test_helper"

class CountryProfileTest < ActiveSupport::TestCase
  test "valid creation" do
    record = CountryProfile.create!(country_code_alpha3: "USA", country_name: "United States")
    assert record.persisted?
  end

  test "country_code_alpha3 is required" do
    r = CountryProfile.new(country_name: "US")
    assert_not r.valid?
    assert_includes r.errors[:country_code_alpha3], "can't be blank"
  end

  test "country_name is required" do
    r = CountryProfile.new(country_code_alpha3: "USA")
    assert_not r.valid?
    assert_includes r.errors[:country_name], "can't be blank"
  end
end
