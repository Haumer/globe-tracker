require "test_helper"
require "tempfile"

class TradeFlowRefreshServiceTest < ActiveSupport::TestCase
  setup do
    TradeFlowSnapshot.delete_all
    SourceFeedStatus.delete_all
    @previous_env = {
      "STRATEGIC_TRADE_FLOWS_SOURCE_PATH" => ENV["STRATEGIC_TRADE_FLOWS_SOURCE_PATH"],
      "STRATEGIC_TRADE_FLOWS_SOURCE_URL" => ENV["STRATEGIC_TRADE_FLOWS_SOURCE_URL"],
      "COMTRADE_PRIMARY_SECRET" => ENV["COMTRADE_PRIMARY_SECRET"],
      "COMTRADE_SECONDARY_SECRET" => ENV["COMTRADE_SECONDARY_SECRET"],
    }

    ENV["STRATEGIC_TRADE_FLOWS_SOURCE_PATH"] = nil
    ENV["STRATEGIC_TRADE_FLOWS_SOURCE_URL"] = nil
    ENV["COMTRADE_PRIMARY_SECRET"] = nil
    ENV["COMTRADE_SECONDARY_SECRET"] = nil
  end

  teardown do
    @previous_env.each do |key, value|
      ENV[key] = value
    end
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
    assert_equal "csv", status.metadata.fetch("source_mode")
  ensure
    file.close!
  end

  test "refresh prefers keyed comtrade api and bootstraps the latest available period" do
    ENV["COMTRADE_PRIMARY_SECRET"] = "primary-secret"

    stub_request(:get, %r{\Ahttps://comtradeapi\.un\.org/data/v1/getLiveUpdate(?:\?.*)?\z})
      .with { |request| request.uri.query.to_s.include?("subscription-key=primary-secret") }
      .to_return(
        status: 200,
        body: {
          count: 1,
          data: [
            {
              typeCode: "C",
              freqCode: "M",
              classificationCode: "HS",
              reporterCode: "392",
              period: "202501",
              lastUpdated: "2026-03-31T00:00:00Z",
            },
          ],
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, %r{\Ahttps://comtradeapi\.un\.org/data/v1/getDa/C/M/HS(?:\?.*)?\z})
      .with do |request|
        request.uri.query.to_s.include?("subscription-key=primary-secret") &&
          request.uri.query.to_s.include?("period=202501")
      end
      .to_return(
        status: 200,
        body: {
          count: 1,
          data: [
            {
              reporterCode: "392",
              reporterISO: "JPN",
              reporterDesc: "Japan",
              totalRecords: 12,
              lastReleased: "2026-03-31T00:00:00Z",
            },
          ],
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, %r{\Ahttps://comtradeapi\.un\.org/data/v1/get/C/M/HS(?:\?.*)?\z})
      .with do |request|
        query = request.uri.query.to_s
        query.include?("subscription-key=primary-secret") &&
          query.include?("reportercode=392") &&
          query.include?("period=202501") &&
          query.include?("flowCode=M")
      end
      .to_return(
        status: 200,
        body: {
          count: 2,
          data: [
            {
              period: "202501",
              reporterCode: "392",
              reporterISO: "JPN",
              reporterDesc: "Japan",
              flowCode: "M",
              flowDesc: "Imports",
              partnerCode: "784",
              partnerISO: "ARE",
              partnerDesc: "United Arab Emirates",
              cmdCode: "2709",
              cmdDesc: "Petroleum oils and oils obtained from bituminous minerals, crude",
              qty: "2500000",
              qtyUnitAbbr: "tonnes",
              primaryValue: "1500000000",
            },
            {
              period: "202501",
              reporterCode: "392",
              reporterISO: "JPN",
              reporterDesc: "Japan",
              flowCode: "M",
              flowDesc: "Imports",
              partnerCode: "0",
              partnerISO: "W00",
              partnerDesc: "World",
              cmdCode: "2709",
              cmdDesc: "Petroleum oils and oils obtained from bituminous minerals, crude",
              qty: "9999999",
              qtyUnitAbbr: "tonnes",
              primaryValue: "9999999999",
            },
          ],
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    count = TradeFlowRefreshService.new.refresh

    assert_equal 1, count
    assert_equal 1, TradeFlowSnapshot.count

    flow = TradeFlowSnapshot.first
    assert_equal "JPN", flow.reporter_country_code_alpha3
    assert_equal "ARE", flow.partner_country_code_alpha3
    assert_equal "import", flow.flow_direction
    assert_equal "oil_crude", flow.commodity_key
    assert_equal "un_comtrade", flow.source
    assert_equal "comtrade_hs_monthly", flow.dataset
    assert_equal Date.new(2025, 1, 1), flow.period_start
    assert_equal Date.new(2025, 1, 31), flow.period_end
    assert_equal 1_500_000_000.to_d, flow.trade_value_usd

    status = SourceFeedStatus.find_by(feed_key: "un_comtrade:https://comtradeapi.un.org/data/v1/getLiveUpdate")
    assert_equal "success", status.status
    assert_equal 2, status.last_records_fetched
    assert_equal 1, status.last_records_stored
    assert_equal "api", status.metadata.fetch("source_mode")
    assert_equal true, status.metadata.fetch("bootstrap_mode")
    assert_equal 1, status.metadata.fetch("request_groups_processed")
    assert_equal 0, status.metadata.fetch("request_groups_remaining")
    assert_equal [], status.metadata.fetch("pending_request_groups")

    assert_requested(:get, %r{\Ahttps://comtradeapi\.un\.org/data/v1/getDa/C/M/HS(?:\?.*)?\z}, times: 1)
  end

  test "refresh records rate limit state and preserves pending request groups" do
    ENV["COMTRADE_PRIMARY_SECRET"] = "primary-secret"

    stub_request(:get, %r{\Ahttps://comtradeapi\.un\.org/data/v1/getLiveUpdate(?:\?.*)?\z})
      .to_return(
        status: 200,
        body: {
          count: 1,
          data: [
            {
              typeCode: "C",
              freqCode: "M",
              classificationCode: "H6",
              classificationSearchCode: "HS",
              reporterCode: "392",
              reporterISO: "JPN",
              period: "202501",
              lastUpdated: "2026-03-31T00:00:00Z",
            },
          ],
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, %r{\Ahttps://comtradeapi\.un\.org/data/v1/getDa/C/M/HS(?:\?.*)?\z})
      .to_return(
        status: 200,
        body: {
          count: 1,
          data: [
            {
              reporterCode: "392",
              reporterISO: "JPN",
              reporterDesc: "Japan",
              classificationCode: "H6",
              classificationSearchCode: "HS",
              totalRecords: 12,
              lastReleased: "2026-03-31T00:00:00Z",
            },
          ],
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, %r{\Ahttps://comtradeapi\.un\.org/data/v1/get/C/M/HS(?:\?.*)?\z})
      .to_return(
        status: 429,
        headers: { "Retry-After" => "120" },
        body: { message: "Too many requests" }.to_json
      )

    freeze_time do
      count = TradeFlowRefreshService.new.refresh

      assert_equal 0, count

      status = SourceFeedStatus.find_by(feed_key: "un_comtrade:https://comtradeapi.un.org/data/v1/getLiveUpdate")
      assert_equal "rate_limited", status.status
      assert_equal 429, status.last_http_status
      assert_equal "api", status.metadata.fetch("source_mode")
      assert_equal 1, status.metadata.fetch("pending_request_groups").size
      assert_equal (Time.current + 120.seconds).iso8601, status.metadata.fetch("retry_after_at")
    end
  end
end
