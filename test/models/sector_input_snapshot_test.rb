require "test_helper"

class SectorInputSnapshotTest < ActiveSupport::TestCase
  test "valid creation" do
    record = SectorInputSnapshot.create!(
      scope_key: "global", sector_key: "energy", sector_name: "Energy",
      input_kind: "commodity", input_key: "crude_oil",
      period_year: 2024, source: "oecd", dataset: "icio"
    )
    assert record.persisted?
  end

  test "source is required" do
    r = SectorInputSnapshot.new(scope_key: "global", sector_key: "e", sector_name: "E", input_kind: "c", input_key: "o", period_year: 2024, dataset: "x")
    assert_not r.valid?
    assert_includes r.errors[:source], "can't be blank"
  end

  test "dataset is required" do
    r = SectorInputSnapshot.new(scope_key: "global", sector_key: "e", sector_name: "E", input_kind: "c", input_key: "o", period_year: 2024, source: "x")
    assert_not r.valid?
    assert_includes r.errors[:dataset], "can't be blank"
  end

  test "latest_first scope orders by period_year desc" do
    old = SectorInputSnapshot.create!(
      scope_key: "global", sector_key: "energy", sector_name: "Energy",
      input_kind: "commodity", input_key: "oil",
      period_year: 2020, source: "oecd", dataset: "icio"
    )
    recent = SectorInputSnapshot.create!(
      scope_key: "global", sector_key: "energy", sector_name: "Energy",
      input_kind: "commodity", input_key: "gas",
      period_year: 2024, source: "oecd", dataset: "icio"
    )
    results = SectorInputSnapshot.latest_first
    assert_operator results.index(recent), :<, results.index(old)
  end
end
