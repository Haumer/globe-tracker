require "test_helper"

class Api::CommoditiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @now = Time.current
    CommodityPrice.create!(
      symbol: "XAU", category: "commodity", name: "Gold",
      price: 2300.50, change_pct: 1.2, unit: "USD/oz",
      latitude: 26.2, longitude: 28.0, region: "South Africa",
      recorded_at: @now,
    )
    CommodityPrice.create!(
      symbol: "EUR", category: "currency", name: "Euro",
      price: 1.08, change_pct: -0.3, unit: "USD",
      latitude: 50.1, longitude: 8.7, region: "Germany",
      recorded_at: @now,
    )
  end

  test "GET /api/commodities returns prices" do
    get "/api/commodities"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Hash, data
    assert_kind_of Array, data["prices"]
    assert data["prices"].length >= 2
  end

  test "prices contain expected fields" do
    get "/api/commodities"
    data = JSON.parse(response.body)

    gold = data["prices"].find { |p| p["symbol"] == "XAU" }
    assert_not_nil gold
    assert_equal "commodity", gold["category"]
    assert_equal "Gold", gold["name"]
    assert_in_delta 2300.50, gold["price"], 0.01
    assert_in_delta 1.2, gold["change_pct"], 0.01
  end

  test "category filter works" do
    get "/api/commodities", params: { category: "currency" }
    data = JSON.parse(response.body)

    symbols = data["prices"].map { |p| p["symbol"] }
    assert_includes symbols, "EUR"
    assert_not_includes symbols, "XAU"
  end
end
