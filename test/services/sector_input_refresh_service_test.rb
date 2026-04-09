require "test_helper"

class SectorInputRefreshServiceTest < ActiveSupport::TestCase
  setup do
    @service = SectorInputRefreshService.new
    @original_path = ENV["SECTOR_INPUTS_SOURCE_PATH"]
    @original_url = ENV["SECTOR_INPUTS_SOURCE_URL"]
  end

  teardown do
    ENV["SECTOR_INPUTS_SOURCE_PATH"] = @original_path
    ENV["SECTOR_INPUTS_SOURCE_URL"] = @original_url
  end

  test "refresh returns 0 when no source configured" do
    ENV["SECTOR_INPUTS_SOURCE_PATH"] = nil
    ENV["SECTOR_INPUTS_SOURCE_URL"] = nil
    # Make sure the default path doesn't exist either
    default_path = SectorInputRefreshService::DEFAULT_SOURCE_PATH
    skip("Default file exists - cannot test disabled path") if File.exist?(default_path)

    SourceFeedStatusRecorder.stub(:record, nil) do
      result = @service.refresh

      assert_equal 0, result
    end
  end

  test "build_record returns nil when sector_key is blank" do
    row = { "sector_key" => "", "input_key" => "oil", "input_kind" => "commodity", "period_year" => "2023" }

    result = @service.send(:build_record, row, Time.current)

    assert_nil result
  end

  test "build_record returns nil when input_key is blank" do
    row = { "sector_key" => "industry", "input_key" => "", "input_kind" => "commodity", "period_year" => "2023" }

    result = @service.send(:build_record, row, Time.current)

    assert_nil result
  end

  test "build_record returns nil when period_year is blank" do
    row = { "sector_key" => "industry", "input_key" => "oil", "input_kind" => "commodity", "period_year" => "" }

    result = @service.send(:build_record, row, Time.current)

    assert_nil result
  end

  test "build_record returns valid hash for complete row" do
    row = {
      "sector_key" => "industry",
      "input_key" => "oil_crude",
      "input_kind" => "commodity",
      "period_year" => "2023",
      "country_iso3" => "DEU",
      "country_iso2" => "DE",
      "country_name" => "Germany",
      "sector_name" => "Industry",
      "input_name" => "Crude Oil",
      "coefficient" => "0.042",
      "source" => "oecd",
      "dataset" => "icio",
    }
    now = Time.current

    result = @service.send(:build_record, row, now)

    assert_not_nil result
    assert_equal "DEU", result[:scope_key]
    assert_equal "DE", result[:country_code]
    assert_equal "DEU", result[:country_code_alpha3]
    assert_equal "Germany", result[:country_name]
    assert_equal "industry", result[:sector_key]
    assert_equal "oil_crude", result[:input_key]
    assert_equal "commodity", result[:input_kind]
    assert_equal 2023, result[:period_year]
    assert_in_delta 0.042, result[:coefficient].to_f, 0.001
  end

  test "build_record defaults scope_key to global when no country" do
    row = {
      "sector_key" => "industry",
      "input_key" => "oil",
      "input_kind" => "commodity",
      "period_year" => "2023",
    }

    result = @service.send(:build_record, row, Time.current)

    assert_equal "global", result[:scope_key]
  end

  test "value_for tries multiple keys" do
    row = { "country_iso2" => "DE" }

    result = @service.send(:value_for, row, "country_code", "country_iso2")

    assert_equal "DE", result
  end

  test "value_for returns nil when no keys match" do
    row = { "other" => "value" }

    result = @service.send(:value_for, row, "missing_key")

    assert_nil result
  end

  test "integer_for converts to integer" do
    row = { "period_year" => "2023" }

    result = @service.send(:integer_for, row, "period_year")

    assert_equal 2023, result
  end

  test "integer_for returns nil for blank value" do
    row = { "period_year" => "" }

    result = @service.send(:integer_for, row, "period_year")

    assert_nil result
  end

  test "decimal_for converts to decimal" do
    row = { "coefficient" => "0.042" }

    result = @service.send(:decimal_for, row, "coefficient")

    assert_in_delta 0.042, result.to_f, 0.0001
  end

  test "normalize_iso2 returns valid 2-letter code" do
    assert_equal "DE", @service.send(:normalize_iso2, "de")
    assert_equal "US", @service.send(:normalize_iso2, "us")
  end

  test "normalize_iso2 returns nil for invalid code" do
    assert_nil @service.send(:normalize_iso2, "DEU")
    assert_nil @service.send(:normalize_iso2, "")
    assert_nil @service.send(:normalize_iso2, nil)
  end

  test "SOURCE_STATUS has required keys" do
    status = SectorInputRefreshService::SOURCE_STATUS

    assert_equal "sector_inputs", status[:provider]
    assert_not_nil status[:display_name]
    assert_not_nil status[:feed_kind]
  end
end
