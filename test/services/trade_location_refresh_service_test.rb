require "test_helper"
require "tempfile"

class TradeLocationRefreshServiceTest < ActiveSupport::TestCase
  setup do
    TradeLocation.delete_all
    SourceFeedStatus.delete_all
    @previous_env = ENV["TRADE_LOCATIONS_SOURCE_PATH"]
  end

  teardown do
    ENV["TRADE_LOCATIONS_SOURCE_PATH"] = @previous_env
  end

  test "refresh imports trade locations from unlocode-style csv" do
    file = Tempfile.new(["trade_locations", ".csv"])
    file.write <<~CSV
      Country,LOCODE,Name,Function,Coordinates,Status
      AE,DXB,Dubai,1-----,2516N 05518E,active
    CSV
    file.flush

    ENV["TRADE_LOCATIONS_SOURCE_PATH"] = file.path

    count = TradeLocationRefreshService.new.refresh

    assert_equal 1, count
    assert_equal 1, TradeLocation.count

    location = TradeLocation.first
    assert_equal "AEDXB", location.locode
    assert_equal "AE", location.country_code
    assert_equal "port", location.location_kind
    assert_in_delta 25.2667, location.latitude, 0.001
    assert_in_delta 55.3, location.longitude, 0.001

    status = SourceFeedStatus.find_by(feed_key: "trade_locations:#{file.path}")
    assert_equal "success", status.status
  ensure
    file.close!
  end
end
