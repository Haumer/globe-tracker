require "test_helper"

class SourceCatalogTest < ActiveSupport::TestCase
  test "entries returns an array" do
    result = SourceCatalog.entries

    assert_kind_of Array, result
  end

  test "entries is non-empty" do
    result = SourceCatalog.entries

    assert result.size > 0
  end

  test "each entry has required icon and title" do
    SourceCatalog.entries.each do |entry|
      assert entry[:icon].present?, "Entry missing icon: #{entry.inspect}"
      assert entry[:title].present?, "Entry missing title: #{entry.inspect}"
    end
  end

  test "each entry has a status" do
    SourceCatalog.entries.each do |entry|
      assert entry[:status].present?, "Entry missing status: #{entry[:title]}"
    end
  end

  test "entries include known sources" do
    titles = SourceCatalog.entries.map { |e| e[:title] }

    assert_includes titles, "ADS-B Exchange"
    assert_includes titles, "OpenSky Network"
    assert_includes titles, "USGS Earthquakes"
    assert_includes titles, "NASA FIRMS"
    assert_includes titles, "GDELT Project"
  end

  test "LIVE sources have live status_class" do
    live_entries = SourceCatalog.entries.select { |e| e[:status] == "LIVE" }

    live_entries.each do |entry|
      assert_equal "live", entry[:status_class], "LIVE entry #{entry[:title]} missing live status_class"
    end
  end

  test "entries return consistent structure" do
    entry = SourceCatalog.entries.first

    assert_kind_of Hash, entry
    assert entry.key?(:icon)
    assert entry.key?(:title)
    assert entry.key?(:status)
  end
end
