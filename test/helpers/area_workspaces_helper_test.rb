require "test_helper"

class AreaWorkspacesHelperTest < ActionView::TestCase
  include AreaWorkspacesHelper

  test "LAYER_SHORT maps known layers to short codes" do
    assert_equal "fl", AreaWorkspacesHelper::LAYER_SHORT["flights"]
    assert_equal "sh", AreaWorkspacesHelper::LAYER_SHORT["ships"]
    assert_equal "eq", AreaWorkspacesHelper::LAYER_SHORT["earthquakes"]
    assert_equal "mb", AreaWorkspacesHelper::LAYER_SHORT["militaryBases"]
  end

  test "area_workspace_globe_href returns root path with anchor" do
    ws = build_workspace(
      scope_type: "bbox",
      scope_metadata: { center: { lat: 48.2, lng: 16.3 }, radius_km: 500, camera: { heading: 0, pitch: -1.12 } },
      bounds: { lamin: 44.0, lamax: 52.0, lomin: 10.0, lomax: 22.0 },
      default_layers: %w[flights ships],
    )

    href = area_workspace_globe_href(ws)
    assert href.start_with?("/")
    assert href.include?("#")
    assert href.include?("l:fl,sh")
  end

  test "area_workspace_globe_anchor includes region for preset_region" do
    ws = build_workspace(
      scope_type: "preset_region",
      scope_metadata: { region_key: "europe", camera: { heading: 0, pitch: -1.12 } },
      bounds: { lamin: 35.0, lamax: 70.0, lomin: -25.0, lomax: 45.0 },
      default_layers: [],
    )

    anchor = area_workspace_globe_anchor(ws)
    assert anchor.include?("r:europe")
  end

  test "area_workspace_globe_anchor includes countries for country_set" do
    ws = build_workspace(
      scope_type: "country_set",
      scope_metadata: { countries: %w[Germany Austria], camera: { heading: 0, pitch: -1.12 } },
      bounds: { lamin: 46.0, lamax: 55.0, lomin: 5.0, lomax: 17.0 },
      default_layers: [],
    )

    anchor = area_workspace_globe_anchor(ws)
    assert anchor.include?("co:Germany|Austria")
  end

  test "area_workspace_globe_anchor includes circle info for bbox with center" do
    ws = build_workspace(
      scope_type: "bbox",
      scope_metadata: { center: { lat: 48.2, lng: 16.3 }, radius_km: 100, camera: { heading: 0, pitch: -1.12 } },
      bounds: { lamin: 47.0, lamax: 49.0, lomin: 15.0, lomax: 17.0 },
      default_layers: [],
    )

    anchor = area_workspace_globe_anchor(ws)
    assert anchor.include?("ci:48.2000,16.3000,100000")
  end

  private

  def build_workspace(scope_type:, scope_metadata:, bounds:, default_layers:)
    OpenStruct.new(
      scope_type: scope_type,
      scope_metadata: scope_metadata.with_indifferent_access,
      bounds: bounds.with_indifferent_access,
      default_layers: default_layers,
      region_key: scope_metadata[:region_key],
      country_names: Array(scope_metadata[:countries]),
      bounds_hash: bounds.with_indifferent_access,
    )
  end
end
