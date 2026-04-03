module PortTestDataHelper
  def create_port_trade_location(overrides = {})
    TradeLocation.create!(
      {
        locode: "JPTYO",
        country_code: "JP",
        country_code_alpha3: "JPN",
        country_name: "Japan",
        name: "Tokyo",
        normalized_name: "tokyo",
        location_kind: "port",
        function_codes: "1",
        latitude: 35.6764,
        longitude: 139.65,
        status: "active",
        source: "test_feed",
        fetched_at: Time.current,
        metadata: {
          "flow_types" => %w[trade container],
          "harbor_size" => "large",
        },
      }.merge(overrides)
    )
  end

  def create_country_dependency(overrides = {})
    CountryCommodityDependency.create!(
      {
        country_code: "JP",
        country_code_alpha3: "JPN",
        country_name: "Japan",
        commodity_key: "lng",
        commodity_name: "Liquefied Natural Gas",
        dependency_score: 0.74,
        metadata: { "estimated" => true },
        fetched_at: Time.current,
      }.merge(overrides)
    )
  end
end
