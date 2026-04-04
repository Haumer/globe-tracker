require "test_helper"

class ShippingLaneMapServiceTest < ActiveSupport::TestCase
  include ShippingLaneTestDataHelper

  test "builds modeled east asia energy lane with export hub stopovers and destination port" do
    create_shipping_dependency(import_share_gdp_pct: 1.4)
    create_shipping_exposure(
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )
    create_shipping_exposure(
      chokepoint_key: "malacca",
      chokepoint_name: "Strait of Malacca",
      exposure_score: 0.51,
      metadata: {
        "estimated" => true,
        "support_types" => ["estimated_route_prior"],
        "requires_any_source_chokepoint" => ["hormuz"],
      }
    )

    lanes = ShippingLaneMapService.lanes
    lane = lanes.find { |item| item[:id] == "kor-lng" }

    assert lane.present?
    assert_equal "modeled", lane[:status]
    assert_equal "Ras Laffan", lane.dig(:source_anchor, :name)
    assert_equal "Ulsan", lane.dig(:destination_anchor, :name)
    assert_equal ["Strait of Hormuz", "Colombo", "Strait of Malacca", "Singapore"],
      lane[:waypoints].map { |waypoint| waypoint[:name] }
    assert_includes lane[:path_points].map { |point| point[:name] }, "Persian Gulf"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Gulf of Oman"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Arabian Sea"
    assert_includes lane[:path_points].map { |point| point[:name] }, "South China Sea"
    assert_includes lane[:path_points].map { |point| point[:name] }, "East China Sea"
    assert_equal ["Strait of Hormuz", "Strait of Malacca"], lane[:chokepoints].map { |cp| cp[:name] }
    assert_equal "commodity:lng", lane.dig(:ontology, "commodity_node_id")
  end

  test "uses supplier trade locations when observed partner data exists" do
    create_shipping_dependency(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.66,
      top_partner_country_code: "AE",
      top_partner_country_code_alpha3: "ARE",
      top_partner_country_name: "United Arab Emirates",
      top_partner_share_pct: 41.2,
      metadata: {
        "partner_breakdown" => [
          { "country_code" => "AE", "country_code_alpha3" => "ARE", "country_name" => "United Arab Emirates", "share_pct" => 41.2 },
        ],
      },
      fetched_at: Time.current
    )

    create_trade_location

    create_shipping_exposure(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.43,
      dependency_score: 0.66,
      supplier_share_pct: 41.2,
      metadata: {
        "support_types" => ["direct_supplier"],
        "supporting_partner_names" => ["United Arab Emirates"],
        "supporting_partner_codes" => ["ARE"],
      },
      fetched_at: Time.current
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "jpn-oil_crude" }

    assert lane.present?
    assert_equal "observed", lane[:status]
    assert_equal "Jebel Ali", lane.dig(:source_anchor, :name)
    assert_equal "United Arab Emirates", lane.dig(:top_partners, 0, :country_name)
  end

  test "prefers the strongest required source chokepoint for a route prior" do
    create_shipping_dependency(
      commodity_key: "oil_refined",
      commodity_name: "Refined Petroleum",
      dependency_score: 0.68
    )
    create_shipping_exposure(
      commodity_key: "oil_refined",
      commodity_name: "Refined Petroleum",
      exposure_score: 0.58,
      dependency_score: 0.68,
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )
    create_shipping_exposure(
      commodity_key: "oil_refined",
      commodity_name: "Refined Petroleum",
      chokepoint_key: "mozambique",
      chokepoint_name: "Mozambique Channel",
      exposure_score: 0.33,
      dependency_score: 0.68,
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )
    create_shipping_exposure(
      commodity_key: "oil_refined",
      commodity_name: "Refined Petroleum",
      chokepoint_key: "malacca",
      chokepoint_name: "Strait of Malacca",
      exposure_score: 0.49,
      dependency_score: 0.68,
      metadata: {
        "estimated" => true,
        "support_types" => ["estimated_route_prior"],
        "requires_any_source_chokepoint" => ["hormuz", "mozambique"],
      }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "kor-oil_refined" }

    assert lane.present?
    assert_equal ["Strait of Hormuz", "Strait of Malacca"], lane[:chokepoints].map { |item| item[:name] }
    refute_includes lane[:waypoints].map { |item| item[:name] }, "Mozambique Channel"
  end

  test "adds maritime approach waypoints for northwest europe routes" do
    create_shipping_dependency(
      country_code: "DE",
      country_code_alpha3: "DEU",
      country_name: "Germany",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.61
    )
    create_shipping_exposure(
      country_code: "DE",
      country_code_alpha3: "DEU",
      country_name: "Germany",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "bab_el_mandeb",
      chokepoint_name: "Bab el-Mandeb",
      exposure_score: 0.34,
      dependency_score: 0.61,
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )
    create_shipping_exposure(
      country_code: "DE",
      country_code_alpha3: "DEU",
      country_name: "Germany",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "suez",
      chokepoint_name: "Suez Canal",
      exposure_score: 0.29,
      dependency_score: 0.61,
      metadata: {
        "estimated" => true,
        "support_types" => ["estimated_route_prior"],
        "requires_any_source_chokepoint" => ["bab_el_mandeb"],
      }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "deu-oil_crude" }

    assert lane.present?
    assert_equal "Hamburg", lane.dig(:destination_anchor, :name)
    assert_equal ["Bab el-Mandeb", "Suez Canal", "Port Said", "Strait of Gibraltar", "Dover", "Cuxhaven"],
      lane[:waypoints].map { |item| item[:name] }
    assert_includes lane[:path_points].map { |point| point[:name] }, "Red Sea"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Eastern Mediterranean"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Sicily Channel"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Western Mediterranean"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Bay of Biscay"
    assert_includes lane[:path_points].map { |point| point[:name] }, "North Sea"
    refute_includes lane[:path_points].map { |point| point[:name] }, "Piraeus"
    refute_includes lane[:path_points].map { |point| point[:name] }, "Valletta"
  end

  test "dedupes destination ports already present in route waypoints" do
    create_shipping_dependency(
      country_code: "GR",
      country_code_alpha3: "GRC",
      country_name: "Greece",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.52
    )
    create_shipping_exposure(
      country_code: "GR",
      country_code_alpha3: "GRC",
      country_name: "Greece",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "bab_el_mandeb",
      chokepoint_name: "Bab el-Mandeb",
      exposure_score: 0.28,
      dependency_score: 0.52,
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )
    create_shipping_exposure(
      country_code: "GR",
      country_code_alpha3: "GRC",
      country_name: "Greece",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "suez",
      chokepoint_name: "Suez Canal",
      exposure_score: 0.24,
      dependency_score: 0.52,
      metadata: {
        "estimated" => true,
        "support_types" => ["estimated_route_prior"],
        "requires_any_source_chokepoint" => ["bab_el_mandeb"],
      }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "grc-oil_crude" }

    assert lane.present?
    assert_equal "Piraeus", lane.dig(:destination_anchor, :name)
    assert_equal 0, lane[:waypoints].count { |item| item[:name] == "Piraeus" }
    assert_includes lane[:path_points].map { |point| point[:name] }, "Piraeus"
  end

  test "falls back to a country anchor when no import port is known" do
    create_shipping_dependency(
      country_code: "KE",
      country_code_alpha3: "KEN",
      country_name: "Kenya",
      commodity_key: "oil_refined",
      commodity_name: "Refined Petroleum",
      dependency_score: 0.57
    )
    create_shipping_exposure(
      country_code: "KE",
      country_code_alpha3: "KEN",
      country_name: "Kenya",
      commodity_key: "oil_refined",
      commodity_name: "Refined Petroleum",
      exposure_score: 0.44,
      dependency_score: 0.57,
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "ken-oil_refined" }

    assert lane.present?
    assert_equal "country_anchor", lane.dig(:destination_anchor, :kind)
    assert_equal "import_country_anchor", lane.dig(:destination_anchor, :role)
    assert_equal "Kenya", lane.dig(:destination_anchor, :name)
    assert_nil lane.dig(:destination_anchor, :lat)
    assert_nil lane.dig(:destination_anchor, :lng)
  end

  test "selects an atlantic us port for middle east to atlantic market routes" do
    create_shipping_dependency(
      country_code: "US",
      country_code_alpha3: "USA",
      country_name: "United States",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.58
    )
    create_shipping_exposure(
      country_code: "US",
      country_code_alpha3: "USA",
      country_name: "United States",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.41,
      dependency_score: 0.58,
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "usa-oil_crude" }

    assert lane.present?
    assert_equal "New York", lane.dig(:destination_anchor, :name)
    assert_includes lane[:waypoints].map { |point| point[:name] }, "Strait of Gibraltar"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Azores Corridor"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Western Atlantic"
  end

  test "selects a pacific us port for panama canal routes" do
    create_shipping_dependency(
      country_code: "US",
      country_code_alpha3: "USA",
      country_name: "United States",
      commodity_key: "lng",
      commodity_name: "Liquefied Natural Gas",
      dependency_score: 0.61
    )
    create_shipping_exposure(
      country_code: "US",
      country_code_alpha3: "USA",
      country_name: "United States",
      commodity_key: "lng",
      commodity_name: "Liquefied Natural Gas",
      chokepoint_key: "panama",
      chokepoint_name: "Panama Canal",
      exposure_score: 0.46,
      dependency_score: 0.61,
      metadata: { "estimated" => true, "support_types" => ["estimated_route_prior"] }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "usa-lng" }

    assert lane.present?
    assert_equal "Houston", lane.dig(:source_anchor, :name)
    assert_equal "Long Beach", lane.dig(:destination_anchor, :name)
    assert_includes lane[:waypoints].map { |point| point[:name] }, "Panama Canal"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Balboa"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Eastern Pacific"
  end

  test "supports panama canal routes into east asia when panama exposure is present" do
    create_shipping_dependency(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "lng",
      commodity_name: "Liquefied Natural Gas",
      dependency_score: 0.59
    )
    create_shipping_exposure(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "lng",
      commodity_name: "Liquefied Natural Gas",
      chokepoint_key: "panama",
      chokepoint_name: "Panama Canal",
      exposure_score: 0.44,
      dependency_score: 0.59,
      metadata: { "estimated" => true, "support_types" => ["estimated_route_prior"] }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "jpn-lng" }

    assert lane.present?
    assert_equal "Houston", lane.dig(:source_anchor, :name)
    assert_equal "Yokohama", lane.dig(:destination_anchor, :name)
    assert_equal ["Panama Canal", "Balboa"], lane[:waypoints].map { |point| point[:name] }
    assert_includes lane[:path_points].map { |point| point[:name] }, "North Pacific"
    assert_includes lane[:path_points].map { |point| point[:name] }, "East China Sea"
  end

  test "supports taiwan strait routes into pacific semiconductor markets" do
    create_shipping_dependency(
      country_code: "US",
      country_code_alpha3: "USA",
      country_name: "United States",
      commodity_key: "semiconductors",
      commodity_name: "Semiconductors",
      dependency_score: 0.56
    )
    create_shipping_exposure(
      country_code: "US",
      country_code_alpha3: "USA",
      country_name: "United States",
      commodity_key: "semiconductors",
      commodity_name: "Semiconductors",
      chokepoint_key: "taiwan_strait",
      chokepoint_name: "Taiwan Strait",
      exposure_score: 0.42,
      dependency_score: 0.56,
      metadata: { "estimated" => true, "support_types" => ["estimated_route_prior"] }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "usa-semiconductors" }

    assert lane.present?
    assert_equal "Kaohsiung", lane.dig(:source_anchor, :name)
    assert_equal "Long Beach", lane.dig(:destination_anchor, :name)
    assert_equal ["Taiwan Strait"], lane[:waypoints].map { |point| point[:name] }
    assert_includes lane[:path_points].map { |point| point[:name] }, "North Pacific"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Eastern Pacific"
  end

  test "keeps alternative chokepoints out of a single modeled oceania route" do
    create_shipping_dependency(
      country_code: "NZ",
      country_code_alpha3: "NZL",
      country_name: "New Zealand",
      commodity_key: "lng",
      commodity_name: "Liquefied Natural Gas",
      dependency_score: 0.63
    )
    create_shipping_exposure(
      country_code: "NZ",
      country_code_alpha3: "NZL",
      country_name: "New Zealand",
      commodity_key: "lng",
      commodity_name: "Liquefied Natural Gas",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.33,
      dependency_score: 0.63,
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )
    create_shipping_exposure(
      country_code: "NZ",
      country_code_alpha3: "NZL",
      country_name: "New Zealand",
      commodity_key: "lng",
      commodity_name: "Liquefied Natural Gas",
      chokepoint_key: "malacca",
      chokepoint_name: "Strait of Malacca",
      exposure_score: 0.36,
      dependency_score: 0.63,
      metadata: {
        "estimated" => true,
        "support_types" => ["estimated_route_prior"],
        "requires_any_source_chokepoint" => ["hormuz"],
      }
    )
    create_shipping_exposure(
      country_code: "NZ",
      country_code_alpha3: "NZL",
      country_name: "New Zealand",
      commodity_key: "lng",
      commodity_name: "Liquefied Natural Gas",
      chokepoint_key: "panama",
      chokepoint_name: "Panama Canal",
      exposure_score: 0.22,
      dependency_score: 0.63,
      metadata: { "estimated" => true, "support_types" => ["estimated_route_prior"] }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "nzl-lng" }

    assert lane.present?
    assert_equal ["Strait of Hormuz", "Colombo", "Strait of Malacca", "Singapore"],
      lane[:waypoints].map { |point| point[:name] }
    refute_includes lane[:waypoints].map { |point| point[:name] }, "Panama Canal"
    refute_includes lane[:path_points].map { |point| point[:name] }, "Panama Canal"
    refute_includes lane[:path_points].map { |point| point[:name] }, "Balboa"
  end

  test "builds strategic fallback lanes from country profiles when dependencies are absent" do
    CountryProfile.create!(
      country_code: "CA",
      country_code_alpha3: "CAN",
      country_name: "Canada",
      latest_year: 2024,
      imports_goods_services_pct_gdp: 35.0,
      exports_goods_services_pct_gdp: 33.0,
      energy_imports_net_pct_energy_use: 8.0,
      metadata: {},
      fetched_at: Time.current
    )
    CountrySectorProfile.create!(
      country_code: "CA",
      country_code_alpha3: "CAN",
      country_name: "Canada",
      sector_key: "industry",
      sector_name: "Industry",
      period_year: 2024,
      share_pct: 31.0,
      rank: 1,
      metadata: {},
      fetched_at: Time.current
    )
    CountrySectorProfile.create!(
      country_code: "CA",
      country_code_alpha3: "CAN",
      country_name: "Canada",
      sector_key: "manufacturing",
      sector_name: "Manufacturing",
      period_year: 2024,
      share_pct: 22.0,
      rank: 2,
      metadata: {},
      fetched_at: Time.current
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "can-oil_crude" }

    assert lane.present?
    assert_equal "modeled", lane[:status]
    assert_equal "Ras Tanura", lane.dig(:source_anchor, :name)
    assert_equal "Halifax", lane.dig(:destination_anchor, :name)
    assert_includes lane[:waypoints].map { |point| point[:name] }, "Strait of Gibraltar"
    assert_includes lane.dig(:metadata, "support_types"), "strategic_corridor"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Azores Corridor"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Western Atlantic"
  end

  test "routes south atlantic brazil lanes around the cape of good hope" do
    create_shipping_dependency(
      country_code: "BR",
      country_code_alpha3: "BRA",
      country_name: "Brazil",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      dependency_score: 0.57
    )
    create_shipping_exposure(
      country_code: "BR",
      country_code_alpha3: "BRA",
      country_name: "Brazil",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.39,
      dependency_score: 0.57,
      metadata: { "estimated" => true, "support_types" => ["estimated_macro_prior"] }
    )

    lane = ShippingLaneMapService.lanes.find { |item| item[:id] == "bra-oil_crude" }

    assert lane.present?
    assert_equal "Santos", lane.dig(:destination_anchor, :name)
    assert_equal ["Strait of Hormuz", "Mozambique Channel", "Cape of Good Hope"],
      lane[:waypoints].map { |point| point[:name] }
    assert_includes lane[:path_points].map { |point| point[:name] }, "Western Indian Ocean"
    assert_includes lane[:path_points].map { |point| point[:name] }, "Cape of Good Hope"
    assert_includes lane[:path_points].map { |point| point[:name] }, "South Atlantic South"
  end

  test "exposes baseline shipping corridors including cape routes" do
    corridors = ShippingLaneMapService.corridors

    assert_operator corridors.size, :>, 20
    assert_includes corridors.map { |corridor| corridor[:name] }, "Mozambique Channel to Cape of Good Hope"
    assert_includes corridors.map { |corridor| corridor[:name] }, "South Pacific to Cape Horn"
  end
end
