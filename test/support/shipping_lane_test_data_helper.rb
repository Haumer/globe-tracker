module ShippingLaneTestDataHelper
  def create_shipping_dependency(overrides = {})
    CountryCommodityDependency.create!(
      {
        country_code: "KR",
        country_code_alpha3: "KOR",
        country_name: "Korea, Rep.",
        commodity_key: "lng",
        commodity_name: "Liquefied Natural Gas",
        dependency_score: 0.71,
        metadata: { "estimated" => true },
        fetched_at: Time.current,
      }.merge(overrides)
    )
  end

  def create_shipping_exposure(overrides = {})
    CountryChokepointExposure.create!(
      {
        country_code: "KR",
        country_code_alpha3: "KOR",
        country_name: "Korea, Rep.",
        commodity_key: "lng",
        commodity_name: "Liquefied Natural Gas",
        chokepoint_key: "hormuz",
        chokepoint_name: "Strait of Hormuz",
        exposure_score: 0.62,
        dependency_score: 0.71,
        supplier_share_pct: 0,
        metadata: { "estimated" => true },
        fetched_at: Time.current,
      }.merge(overrides)
    )
  end

  def create_trade_location(overrides = {})
    TradeLocation.create!(
      {
        locode: "AEJEA",
        country_code: "AE",
        country_code_alpha3: "ARE",
        country_name: "United Arab Emirates",
        name: "Jebel Ali",
        normalized_name: "jebel ali",
        location_kind: "port",
        function_codes: "1",
        latitude: 25.013,
        longitude: 55.061,
        status: "active",
        source: "test",
        fetched_at: Time.current,
        metadata: {},
      }.merge(overrides)
    )
  end
end
