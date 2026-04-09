require "test_helper"

class CommoditySiteCatalogTest < ActiveSupport::TestCase
  test "all returns array" do
    result = CommoditySiteCatalog.all

    assert_kind_of Array, result
  end

  test "all returns empty array when file does not exist" do
    original = CommoditySiteCatalog::DATA_FILE
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, Rails.root.join("tmp", "nonexistent_commodity_sites.json"))

    result = CommoditySiteCatalog.all
    assert_equal [], result
  ensure
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, original)
  end

  test "all returns empty array on invalid JSON" do
    path = Rails.root.join("tmp", "bad_commodity_sites.json")
    File.write(path, "not valid json{{{")

    original = CommoditySiteCatalog::DATA_FILE
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, path)

    result = CommoditySiteCatalog.all
    assert_equal [], result
  ensure
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, original)
    File.delete(path) if File.exist?(path)
  end

  test "last_modified returns nil when file does not exist" do
    original = CommoditySiteCatalog::DATA_FILE
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, Rails.root.join("tmp", "nonexistent.json"))

    result = CommoditySiteCatalog.last_modified
    assert_nil result
  ensure
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, original)
  end

  test "last_modified returns a Time when file exists" do
    path = Rails.root.join("tmp", "existing_commodity_sites.json")
    File.write(path, "[]")

    original = CommoditySiteCatalog::DATA_FILE
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, path)

    result = CommoditySiteCatalog.last_modified
    assert_kind_of Time, result
  ensure
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, original)
    File.delete(path) if File.exist?(path)
  end

  test "etag returns missing marker when file does not exist" do
    original = CommoditySiteCatalog::DATA_FILE
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, Rails.root.join("tmp", "nonexistent.json"))

    result = CommoditySiteCatalog.etag
    assert_equal "commodity-sites:missing", result
  ensure
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, original)
  end

  test "etag includes size and mtime when file exists" do
    path = Rails.root.join("tmp", "etag_commodity_sites.json")
    File.write(path, "[]")

    original = CommoditySiteCatalog::DATA_FILE
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, path)

    result = CommoditySiteCatalog.etag
    assert_match(/\Acommodity-sites:\d+:\d+\z/, result)
  ensure
    CommoditySiteCatalog.send(:remove_const, :DATA_FILE)
    CommoditySiteCatalog.const_set(:DATA_FILE, original)
    File.delete(path) if File.exist?(path)
  end
end
