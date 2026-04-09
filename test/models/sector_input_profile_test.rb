require "test_helper"

class SectorInputProfileTest < ActiveSupport::TestCase
  test "valid creation" do
    record = SectorInputProfile.create!(
      scope_key: "global", sector_key: "energy", sector_name: "Energy",
      input_kind: "commodity", input_key: "crude_oil", period_year: 2024
    )
    assert record.persisted?
  end

  test "scope_key is required" do
    r = SectorInputProfile.new(sector_key: "e", sector_name: "E", input_kind: "c", input_key: "o", period_year: 2024)
    r.scope_key = nil
    assert_not r.valid?
    assert_includes r.errors[:scope_key], "can't be blank"
  end

  test "sector_key is required" do
    r = SectorInputProfile.new(scope_key: "global", sector_name: "E", input_kind: "c", input_key: "o", period_year: 2024)
    assert_not r.valid?
    assert_includes r.errors[:sector_key], "can't be blank"
  end

  test "input_kind is required" do
    r = SectorInputProfile.new(scope_key: "global", sector_key: "e", sector_name: "E", input_key: "o", period_year: 2024)
    assert_not r.valid?
    assert_includes r.errors[:input_kind], "can't be blank"
  end

  test "input_key is required" do
    r = SectorInputProfile.new(scope_key: "global", sector_key: "e", sector_name: "E", input_kind: "c", period_year: 2024)
    assert_not r.valid?
    assert_includes r.errors[:input_key], "can't be blank"
  end

  test "period_year is required" do
    r = SectorInputProfile.new(scope_key: "global", sector_key: "e", sector_name: "E", input_kind: "c", input_key: "o")
    assert_not r.valid?
    assert_includes r.errors[:period_year], "can't be blank"
  end
end
