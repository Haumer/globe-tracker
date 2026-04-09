require "test_helper"

class SupplyChainCatalogTest < ActiveSupport::TestCase
  test "WORLD_BANK_SERIES contains expected indicator keys" do
    series = SupplyChainCatalog::WORLD_BANK_SERIES

    assert series.key?("NY.GDP.MKTP.CD")
    assert series.key?("SP.POP.TOTL")
    assert series.key?("NE.IMP.GNFS.ZS")
  end

  test "WORLD_BANK_SERIES entries have required fields" do
    SupplyChainCatalog::WORLD_BANK_SERIES.each do |key, config|
      assert config.key?(:target), "#{key} missing :target"
      assert config.key?(:unit), "#{key} missing :unit"

      case config[:target]
      when :indicator
        assert config.key?(:indicator_key), "#{key} missing :indicator_key"
        assert config.key?(:indicator_name), "#{key} missing :indicator_name"
      when :sector
        assert config.key?(:sector_key), "#{key} missing :sector_key"
        assert config.key?(:sector_name), "#{key} missing :sector_name"
      end
    end
  end

  test "STRATEGIC_COMMODITIES contains expected commodities" do
    commodities = SupplyChainCatalog::STRATEGIC_COMMODITIES

    assert commodities.key?("oil_crude")
    assert commodities.key?("lng")
    assert commodities.key?("semiconductors")
    assert commodities.key?("copper")
    assert commodities.key?("wheat")
  end

  test "STRATEGIC_COMMODITIES entries have name and hs_prefixes" do
    SupplyChainCatalog::STRATEGIC_COMMODITIES.each do |key, config|
      assert config.key?(:name), "#{key} missing :name"
      assert config.key?(:hs_prefixes), "#{key} missing :hs_prefixes"
      assert_kind_of Array, config[:hs_prefixes]
      assert config[:hs_prefixes].any?, "#{key} has empty hs_prefixes"
    end
  end

  test "COMMODITY_FLOW_TYPES maps all strategic commodities" do
    flow_types = SupplyChainCatalog::COMMODITY_FLOW_TYPES

    SupplyChainCatalog::STRATEGIC_COMMODITIES.each_key do |key|
      assert flow_types.key?(key), "#{key} missing from COMMODITY_FLOW_TYPES"
    end
  end

  test "COMMODITY_FLOW_TYPES values are valid symbols" do
    valid_types = %i[oil lng grain semiconductors trade]

    SupplyChainCatalog::COMMODITY_FLOW_TYPES.each do |key, type|
      assert_includes valid_types, type, "#{key} has unexpected flow type: #{type}"
    end
  end

  test "CHOKEPOINT_ROUTE_PRIORS is a non-empty array" do
    priors = SupplyChainCatalog::CHOKEPOINT_ROUTE_PRIORS

    assert_kind_of Array, priors
    assert priors.any?
  end

  test "CHOKEPOINT_ROUTE_PRIORS entries have required fields" do
    SupplyChainCatalog::CHOKEPOINT_ROUTE_PRIORS.each do |prior|
      assert prior.key?(:chokepoint_key), "Missing :chokepoint_key in route prior"
      assert prior.key?(:commodity_keys), "Missing :commodity_keys in route prior"
      assert prior.key?(:multiplier), "Missing :multiplier in route prior"
      assert prior.key?(:route_waypoints), "Missing :route_waypoints in route prior"
      assert_kind_of Array, prior[:commodity_keys]
      assert_kind_of Array, prior[:route_waypoints]
    end
  end

  test "EXPORT_HUB_PRIORS is a hash with array keys" do
    priors = SupplyChainCatalog::EXPORT_HUB_PRIORS

    assert_kind_of Hash, priors
    priors.each do |key, hub|
      assert_kind_of Array, key
      assert_equal 2, key.size
      assert hub.key?(:kind), "Hub missing :kind for #{key}"
      assert hub.key?(:name), "Hub missing :name for #{key}"
      assert hub.key?(:lat), "Hub missing :lat for #{key}"
      assert hub.key?(:lng), "Hub missing :lng for #{key}"
    end
  end

  test "WORLD_BANK_SOURCE has required keys" do
    source = SupplyChainCatalog::WORLD_BANK_SOURCE

    assert_equal "world_bank", source[:provider]
    assert_not_nil source[:display_name]
    assert_not_nil source[:feed_kind]
    assert_not_nil source[:endpoint_url]
  end

  test "SHIPPING_ROUTE_EXTENSIONS is a hash" do
    extensions = SupplyChainCatalog::SHIPPING_ROUTE_EXTENSIONS

    assert_kind_of Hash, extensions
    extensions.each do |country_code, waypoints|
      assert_kind_of String, country_code
      assert_kind_of Array, waypoints
    end
  end
end
