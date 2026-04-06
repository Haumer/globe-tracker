require "test_helper"
require "tempfile"

class EnergyBalanceRefreshServiceTest < ActiveSupport::TestCase
  setup do
    EnergyBalanceSnapshot.delete_all
    CountryIndicatorSnapshot.delete_all
    CountryProfile.delete_all
    SourceFeedStatus.delete_all

    @previous_env = {
      "ENERGY_BALANCES_SOURCE_PATH" => ENV["ENERGY_BALANCES_SOURCE_PATH"],
      "ENERGY_BALANCES_SOURCE_URL" => ENV["ENERGY_BALANCES_SOURCE_URL"],
    }

    ENV["ENERGY_BALANCES_SOURCE_PATH"] = nil
    ENV["ENERGY_BALANCES_SOURCE_URL"] = nil
  end

  teardown do
    @previous_env.each do |key, value|
      ENV[key] = value
    end
  end

  test "refresh imports normalized energy balances from csv source" do
    file = Tempfile.new(["energy_balances", ".csv"])
    file.write <<~CSV
      country_iso2,country_iso3,country_name,commodity_key,metric_key,period_start,period_end,period_type,value_numeric,unit,source,dataset
      JP,JPN,Japan,oil_crude,stocks_days,2025-01,2025-01-31,month,92,days,jodi,normalized_energy_balances
    CSV
    file.flush

    ENV["ENERGY_BALANCES_SOURCE_PATH"] = file.path

    count = EnergyBalanceRefreshService.new.refresh

    assert_equal 1, count
    assert_equal 1, EnergyBalanceSnapshot.count

    snapshot = EnergyBalanceSnapshot.first
    assert_equal "JPN", snapshot.country_code_alpha3
    assert_equal "oil_crude", snapshot.commodity_key
    assert_equal "stocks_days", snapshot.metric_key
    assert_equal 92.to_d, snapshot.value_numeric

    status = SourceFeedStatus.find_by(feed_key: "energy_balances:#{file.path}")
    assert_equal "success", status.status
    assert_equal "normalized_csv", status.metadata.fetch("source_mode")
  ensure
    file.close!
  end

  test "refresh falls back to JODI oil default source and derives stock cover metrics" do
    CountryIndicatorSnapshot.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      indicator_key: "gdp_nominal_usd",
      indicator_name: "GDP Nominal USD",
      period_type: "year",
      period_start: Date.new(2025, 1, 1),
      period_end: Date.new(2025, 12, 31),
      value_numeric: 4_200_000_000_000,
      unit: "usd",
      source: "world_bank",
      dataset: "wdi",
      series_key: "gdp_nominal_usd",
      fetched_at: Time.current
    )

    freeze_time do
      stub_request(:get, "https://www.jodidata.org/_resources/files/downloads/oil-data/annual-csv/primary/primaryyear#{Time.current.year}.csv")
        .to_return(
          status: 200,
          body: <<~CSV,
            REF_AREA,TIME_PERIOD,ENERGY_PRODUCT,FLOW_BREAKDOWN,UNIT_MEASURE,OBS_VALUE,ASSESSMENT_CODE
            JP,#{Time.current.year}-01,CRUDEOIL,CLOSTLV,CONVBBL,6000.0,1
            JP,#{Time.current.year}-01,NGL,CLOSTLV,CONVBBL,2000.0,1
            JP,#{Time.current.year}-01,OTHERCRUDE,CLOSTLV,CONVBBL,1000.0,1
            JP,#{Time.current.year}-01,TOTCRUDE,CLOSTLV,CONVBBL,..,1
            JP,#{Time.current.year}-01,CRUDEOIL,TOTIMPSB,KBD,200.0,1
            JP,#{Time.current.year}-01,NGL,TOTIMPSB,KBD,50.0,1
            JP,#{Time.current.year}-01,OTHERCRUDE,TOTIMPSB,KBD,0.0,1
            JP,#{Time.current.year}-01,TOTCRUDE,TOTIMPSB,KBD,x,1
            JP,#{Time.current.year}-01,CRUDEOIL,TOTEXPSB,KBD,5.0,1
            JP,#{Time.current.year}-01,NGL,TOTEXPSB,KBD,2.0,1
            JP,#{Time.current.year}-01,OTHERCRUDE,TOTEXPSB,KBD,0.0,1
          CSV
          headers: { "Content-Type" => "text/csv" }
        )

      count = EnergyBalanceRefreshService.new.refresh

      assert_equal 4, count
      assert_equal 4, EnergyBalanceSnapshot.count

      closing_stock = EnergyBalanceSnapshot.find_by!(country_code_alpha3: "JPN", commodity_key: "oil_crude", metric_key: "closing_stock_convbbl")
      imports = EnergyBalanceSnapshot.find_by!(country_code_alpha3: "JPN", commodity_key: "oil_crude", metric_key: "imports_kbd")
      stocks_days = EnergyBalanceSnapshot.find_by!(country_code_alpha3: "JPN", commodity_key: "oil_crude", metric_key: "stocks_days")

      assert_equal 9000.to_d, closing_stock.value_numeric
      assert_equal 250.to_d, imports.value_numeric
      assert_equal 36.to_d, stocks_days.value_numeric

      status = SourceFeedStatus.find_by(feed_key: "energy_balances:https://www.jodidata.org/_resources/files/downloads/oil-data/annual-csv/primary/primaryyear#{Time.current.year}.csv")
      assert_equal "success", status.status
      assert_equal "jodi_oil_default", status.metadata.fetch("source_mode")
      assert_equal Time.current.year.to_s, status.metadata.fetch("release_version")
    end
  end
end
