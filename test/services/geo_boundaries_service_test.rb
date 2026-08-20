require "test_helper"

class GeoBoundariesServiceTest < ActiveSupport::TestCase
  test "walks catalog to simplified geometry and returns the features" do
    stub_request(:get, "https://www.geoboundaries.org/api/current/gbOpen/PSE/ADM2/")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { simplifiedGeometryGeoJSON: "https://example.test/pse-adm2.geojson" }.to_json)
    stub_request(:get, "https://example.test/pse-adm2.geojson")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { type: "FeatureCollection",
                         features: [ { type: "Feature", properties: { shapeName: "Gaza" }, geometry: nil } ] }.to_json)

    features = GeoBoundariesService.adm2_features("pse")

    assert_equal 1, features.size
    assert_equal "Gaza", features.first.dig("properties", "shapeName")
  end

  test "a junk code short-circuits without a request" do
    assert_equal [], GeoBoundariesService.adm2_features("regions; drop")
  end

  test "a catalog miss resolves to an empty set" do
    stub_request(:get, "https://www.geoboundaries.org/api/current/gbOpen/VAT/ADM2/")
      .to_return(status: 404, body: "")

    assert_equal [], GeoBoundariesService.adm2_features("VAT")
  end
end
