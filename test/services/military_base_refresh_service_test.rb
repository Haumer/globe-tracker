require "test_helper"

class MilitaryBaseRefreshServiceTest < ActiveSupport::TestCase
  setup do
    @service = MilitaryBaseRefreshService.new
  end

  test "normalize_type maps barracks to army" do
    assert_equal "army", @service.send(:normalize_type, "barracks")
    assert_equal "army", @service.send(:normalize_type, "base")
  end

  test "normalize_type maps naval_base to navy" do
    assert_equal "navy", @service.send(:normalize_type, "naval_base")
    assert_equal "navy", @service.send(:normalize_type, "naval_station")
  end

  test "normalize_type maps airfield to air_force" do
    assert_equal "air_force", @service.send(:normalize_type, "airfield")
    assert_equal "air_force", @service.send(:normalize_type, "air_base")
  end

  test "normalize_type maps nuclear to nuclear" do
    assert_equal "nuclear", @service.send(:normalize_type, "nuclear_explosion_site")
    assert_equal "nuclear", @service.send(:normalize_type, "nuclear")
  end

  test "normalize_type maps missile_site to missile" do
    assert_equal "missile", @service.send(:normalize_type, "missile_site")
    assert_equal "missile", @service.send(:normalize_type, "launchpad")
  end

  test "normalize_type maps training_area to training" do
    assert_equal "training", @service.send(:normalize_type, "training_area")
    assert_equal "training", @service.send(:normalize_type, "range")
  end

  test "normalize_type maps depot to logistics" do
    assert_equal "logistics", @service.send(:normalize_type, "depot")
    assert_equal "logistics", @service.send(:normalize_type, "office")
    assert_equal "logistics", @service.send(:normalize_type, "checkpoint")
  end

  test "normalize_type returns other for unknown types" do
    assert_equal "other", @service.send(:normalize_type, "unknown_type")
    assert_equal "other", @service.send(:normalize_type, "")
  end

  test "parse_element extracts lat/lon from node" do
    el = {
      "type" => "node",
      "id" => 12345,
      "lat" => 48.2,
      "lon" => 16.3,
      "tags" => { "name" => "Test Base", "military" => "barracks" },
    }
    now = Time.current

    result = @service.send(:parse_element, el, now)

    assert_not_nil result
    assert_equal "osm-node-12345", result[:external_id]
    assert_equal "Test Base", result[:name]
    assert_equal "army", result[:base_type]
    assert_in_delta 48.2, result[:latitude], 0.01
    assert_in_delta 16.3, result[:longitude], 0.01
    assert_equal "osm", result[:source]
  end

  test "parse_element extracts lat/lon from center for ways" do
    el = {
      "type" => "way",
      "id" => 99999,
      "center" => { "lat" => 50.0, "lon" => 14.0 },
      "tags" => { "military" => "airfield" },
    }
    now = Time.current

    result = @service.send(:parse_element, el, now)

    assert_not_nil result
    assert_equal "osm-way-99999", result[:external_id]
    assert_equal "air_force", result[:base_type]
    assert_in_delta 50.0, result[:latitude], 0.01
  end

  test "parse_element returns nil when coordinates are missing" do
    el = {
      "type" => "node",
      "id" => 11111,
      "tags" => { "military" => "base" },
    }
    now = Time.current

    result = @service.send(:parse_element, el, now)

    assert_nil result
  end

  test "load_hardcoded_bases persists manual bases" do
    now = Time.current

    count = @service.send(:load_hardcoded_bases, now)

    assert count > 0
    assert MilitaryBase.find_by(external_id: "manual-ramstein").present?
    assert MilitaryBase.find_by(external_id: "manual-incirlik").present?
  end

  test "hardcoded_bases all have required fields" do
    bases = @service.send(:hardcoded_bases)

    bases.each do |base|
      assert base[:external_id].present?, "Missing external_id"
      assert base[:name].present?, "Missing name for #{base[:external_id]}"
      assert base[:base_type].present?, "Missing base_type for #{base[:external_id]}"
      assert base[:latitude].present?, "Missing latitude for #{base[:external_id]}"
      assert base[:longitude].present?, "Missing longitude for #{base[:external_id]}"
    end
  end

  test "REGION_BBOXES contains expected regions" do
    assert MilitaryBaseRefreshService::REGION_BBOXES.key?(:middle_east)
    assert MilitaryBaseRefreshService::REGION_BBOXES.key?(:ukraine_russia)
    assert MilitaryBaseRefreshService::REGION_BBOXES.key?(:east_asia)
    assert MilitaryBaseRefreshService::REGION_BBOXES.key?(:horn_of_africa)
  end

  test "OVERPASS_URL is defined" do
    assert_equal "https://overpass-api.de/api/interpreter", MilitaryBaseRefreshService::OVERPASS_URL
  end
end
