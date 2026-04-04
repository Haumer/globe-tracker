require "test_helper"

class CountryIndicatorRefreshServiceTest < ActiveSupport::TestCase
  setup do
    CountryIndicatorSnapshot.delete_all
    CountrySectorSnapshot.delete_all
    SourceFeedStatus.delete_all

    stub_request(:get, %r{\Ahttps://api\.worldbank\.org/v2/country/all/indicator/}).to_return do |request|
      series_key = request.uri.path.split("/").last
      payload = [
        {
          "page" => 1,
          "pages" => 1,
          "per_page" => "20000",
          "total" => 2,
          "lastupdated" => "2026-03-31",
        },
        [
          {
            "indicator" => { "id" => series_key, "value" => series_key },
            "country" => { "id" => "JP", "value" => "Japan" },
            "countryiso3code" => "JPN",
            "date" => "2024",
            "value" => sample_value_for(series_key),
          },
          {
            "indicator" => { "id" => series_key, "value" => series_key },
            "country" => { "id" => "1W", "value" => "World" },
            "countryiso3code" => "WLD",
            "date" => "2024",
            "value" => 999,
          },
        ],
      ]

      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: payload.to_json,
      }
    end
  end

  test "refresh imports world bank indicators and sector shares" do
    count = CountryIndicatorRefreshService.new.refresh

    assert_equal SupplyChainCatalog::WORLD_BANK_SERIES.size, count
    assert_equal 6, CountryIndicatorSnapshot.count
    assert_equal 4, CountrySectorSnapshot.count

    gdp = CountryIndicatorSnapshot.find_by(country_code_alpha3: "JPN", indicator_key: "gdp_nominal_usd")
    assert_equal "JP", gdp.country_code
    assert_equal Date.new(2024, 1, 1), gdp.period_start
    assert_equal "world_bank", gdp.source

    manufacturing = CountrySectorSnapshot.find_by(country_code_alpha3: "JPN", sector_key: "manufacturing")
    assert_equal "gdp_share_pct", manufacturing.metric_key
    assert_in_delta 19.3, manufacturing.value_numeric.to_f, 0.001

    status = SourceFeedStatus.find_by(feed_key: "world_bank:https://api.worldbank.org/v2")
    assert_equal "success", status.status
    assert_equal SupplyChainCatalog::WORLD_BANK_SERIES.size, status.last_records_stored
  end

  private

  def sample_value_for(series_key)
    {
      "NY.GDP.MKTP.CD" => 4_212_945_000_000.0,
      "NY.GDP.PCAP.CD" => 33_950.1,
      "SP.POP.TOTL" => 124_500_000,
      "NE.IMP.GNFS.ZS" => 21.6,
      "NE.EXP.GNFS.ZS" => 22.1,
      "EG.IMP.CONS.ZS" => 87.4,
      "NV.AGR.TOTL.ZS" => 1.1,
      "NV.IND.TOTL.ZS" => 28.4,
      "NV.IND.MANF.ZS" => 19.3,
      "NV.SRV.TOTL.ZS" => 70.5,
    }.fetch(series_key)
  end
end
