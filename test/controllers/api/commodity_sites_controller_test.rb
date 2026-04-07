require "test_helper"

class Api::CommoditySitesControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/commodity_sites returns commodity site payload" do
    get "/api/commodity_sites"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Hash, data
    assert data["commodity_sites"].is_a?(Array)
    assert data["commodity_sites"].any?
  end

  test "entries include source-backed commodity site fields" do
    get "/api/commodity_sites"
    data = JSON.parse(response.body)
    entry = data.fetch("commodity_sites").first

    assert entry["id"].present?
    assert entry["name"].present?
    assert entry["commodity_key"].present?
    assert entry["lat"].present?
    assert entry["lng"].present?
    assert entry["source_url"].present?
  end

  test "payload spans multiple strategic commodity groups" do
    get "/api/commodity_sites"
    data = JSON.parse(response.body)
    commodity_keys = data.fetch("commodity_sites").map { |entry| entry["commodity_key"] }.uniq

    %w[helium fertilizer lng oil_refined gas_nat copper iron_ore].each do |key|
      assert_includes commodity_keys, key
    end
  end
end
