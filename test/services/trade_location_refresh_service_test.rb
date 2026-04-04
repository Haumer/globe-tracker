require "test_helper"
require "tempfile"

class TradeLocationRefreshServiceTest < ActiveSupport::TestCase
  setup do
    TradeLocation.delete_all
    SourceFeedStatus.delete_all
    @previous_env = ENV["TRADE_LOCATIONS_SOURCE_PATH"]
    @previous_trade_url = ENV["TRADE_LOCATIONS_SOURCE_URL"]
    @previous_wpi_enabled = ENV["WORLD_PORT_INDEX_ENABLED"]
    @previous_wpi_url = ENV["WORLD_PORT_INDEX_SOURCE_URL"]
    @previous_wpi_path = ENV["WORLD_PORT_INDEX_SOURCE_PATH"]
    ENV["WORLD_PORT_INDEX_ENABLED"] = "false"
  end

  teardown do
    ENV["TRADE_LOCATIONS_SOURCE_PATH"] = @previous_env
    ENV["TRADE_LOCATIONS_SOURCE_URL"] = @previous_trade_url
    ENV["WORLD_PORT_INDEX_ENABLED"] = @previous_wpi_enabled
    ENV["WORLD_PORT_INDEX_SOURCE_URL"] = @previous_wpi_url
    ENV["WORLD_PORT_INDEX_SOURCE_PATH"] = @previous_wpi_path
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

  test "refresh imports ports from world port index feature service" do
    ENV["WORLD_PORT_INDEX_ENABLED"] = "true"
    ENV["WORLD_PORT_INDEX_SOURCE_URL"] = "https://example.test/wpi/FeatureServer/0/query"

    CountryProfile.create!(
      country_code: "QA",
      country_code_alpha3: "QAT",
      country_name: "Qatar",
      fetched_at: Time.current
    )

    stub_request(:get, %r{\Ahttps://example\.test/wpi/FeatureServer/0/query\?})
      .to_return(
        status: 200,
        body: {
          features: [
            {
              attributes: {
                "wpinumber" => 40321,
                "main_port_" => "Ras Laffan",
                "unlocode" => "QARLF",
                "countryCode" => "QA",
                "dodwaterbo" => "Persian Gulf",
                "harbor_siz" => "Large",
                "harbor_use" => "Cargo",
                "cargo_pier" => 14.0,
                "oil_termin" => 18.5,
                "lng_termin" => 13.6,
                "maxvesseld" => 14.2
              },
              geometry: { "x" => 51.55, "y" => 25.92 }
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    count = TradeLocationRefreshService.new.refresh

    assert_equal 1, count
    location = TradeLocation.find_by!(locode: "QARLF")
    assert_equal "QA", location.country_code
    assert_equal "QAT", location.country_code_alpha3
    assert_equal "Ras Laffan", location.name
    assert_equal "nga_wpi", location.source
    assert_in_delta 25.92, location.latitude, 0.001
    assert_includes location.metadata.fetch("flow_types"), "oil"
    assert_includes location.metadata.fetch("flow_types"), "lng"
    assert_includes location.metadata.fetch("flow_types"), "gulf"
    assert_in_delta 0.99, location.metadata.fetch("importance"), 0.001

    status = SourceFeedStatus.find_by(feed_key: "nga_wpi:https://example.test/wpi/FeatureServer/0/query")
    assert_equal "success", status.status
  end

  test "refresh falls back to the public mirror when the official wpi endpoint fails" do
    ENV["WORLD_PORT_INDEX_ENABLED"] = "true"
    ENV["WORLD_PORT_INDEX_SOURCE_URL"] = "https://example.test/wpi/FeatureServer/0/query"

    stub_request(:get, %r{\Ahttps://example\.test/wpi/FeatureServer/0/query\?})
      .to_raise(Errno::ECONNRESET)

    stub_request(:get, %r{\Ahttps://services-eu1\.arcgis\.com/.*/World_Port_Index/FeatureServer/0/query\?})
      .to_return(
        status: 200,
        body: {
          features: [
            {
              attributes: {
                "INDEX_NO" => 61110,
                "PORT_NAME" => "MOMBETSU KO",
                "COUNTRY" => "JP",
                "LATITUDE" => 44.35,
                "LONGITUDE" => 143.35,
              },
              geometry: { "x" => 143.35, "y" => 44.35 }
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    count = TradeLocationRefreshService.new.refresh

    assert_equal 1, count
    location = TradeLocation.find_by!(locode: "WPI61110")
    assert_equal "MOMBETSU KO", location.name
    assert_equal "JP", location.country_code
    assert_equal "nga_wpi+mirror", location.source
    assert_equal "mirror", location.metadata["source_variant"]
  end

  test "refresh stores mixed-shape mirror rows with a consistent upsert payload" do
    ENV["WORLD_PORT_INDEX_ENABLED"] = "true"
    ENV["WORLD_PORT_INDEX_SOURCE_URL"] = "https://example.test/wpi/FeatureServer/0/query"

    stub_request(:get, %r{\Ahttps://example\.test/wpi/FeatureServer/0/query\?})
      .to_raise(Errno::ECONNRESET)

    stub_request(:get, %r{\Ahttps://services-eu1\.arcgis\.com/.*/World_Port_Index/FeatureServer/0/query\?})
      .to_return(
        status: 200,
        body: {
          features: [
            {
              attributes: {
                "INDEX_NO" => 61090,
                "PORT_NAME" => "SHAKOTAN",
                "COUNTRY" => "RU",
                "LATITUDE" => 43.866667,
                "LONGITUDE" => 146.833333,
              },
              geometry: { "x" => 146.833333, "y" => 43.866667 }
            },
            {
              attributes: {
                "INDEX_NO" => 61110,
                "PORT_NAME" => "MOMBETSU KO",
                "COUNTRY" => "JP",
                "LATITUDE" => 44.35,
                "LONGITUDE" => 143.35,
                "harbor_siz" => "Large"
              },
              geometry: { "x" => 143.35, "y" => 44.35 }
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    count = TradeLocationRefreshService.new.refresh

    assert_equal 2, count
    assert_equal 2, TradeLocation.where(source: "nga_wpi+mirror").count
  end
end
