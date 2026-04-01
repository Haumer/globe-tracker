require "test_helper"
require "tempfile"

class TradeFlowRefreshServiceTest < ActiveSupport::TestCase
  setup do
    TradeFlowSnapshot.delete_all
    SourceFeedStatus.delete_all
    @previous_env = ENV["STRATEGIC_TRADE_FLOWS_SOURCE_PATH"]
  end

  teardown do
    ENV["STRATEGIC_TRADE_FLOWS_SOURCE_PATH"] = @previous_env
  end

  test "refresh imports normalized strategic trade flows and infers commodity from hs code" do
    file = Tempfile.new(["trade_flows", ".csv"])
    file.write <<~CSV
      reporter_iso2,reporter_iso3,reporter_name,partner_iso2,partner_iso3,partner_name,flow_direction,hs_code,period_start,trade_value_usd,quantity,quantity_unit,source,dataset
      AE,ARE,United Arab Emirates,JP,JPN,Japan,export,2709,2025-01,1500000000,2500000,tonnes,cepii_baci,baci
      KR,KOR,South Korea,US,USA,United States,export,9999,2025-01,100,1,units,cepii_baci,baci
    CSV
    file.flush

    ENV["STRATEGIC_TRADE_FLOWS_SOURCE_PATH"] = file.path

    count = TradeFlowRefreshService.new.refresh

    assert_equal 1, count
    assert_equal 1, TradeFlowSnapshot.count

    flow = TradeFlowSnapshot.first
    assert_equal "ARE", flow.reporter_country_code_alpha3
    assert_equal "JPN", flow.partner_country_code_alpha3
    assert_equal "oil_crude", flow.commodity_key
    assert_equal Date.new(2025, 1, 1), flow.period_start
    assert_equal Date.new(2025, 1, 31), flow.period_end
    assert_equal "month", flow.period_type

    status = SourceFeedStatus.find_by(feed_key: "strategic_trade_flows:#{file.path}")
    assert_equal "success", status.status
    assert_equal 2, status.last_records_fetched
    assert_equal 1, status.last_records_stored
  ensure
    file.close!
  end
end
