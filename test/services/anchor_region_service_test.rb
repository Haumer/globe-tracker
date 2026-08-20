require "test_helper"

class AnchorRegionServiceTest < ActiveSupport::TestCase
  # A two-region world: a square around Gaza with clean codes, and a square
  # around Paris carrying Natural Earth's "-99" iso_a2 quirk.
  def admin1
    {
      "type" => "FeatureCollection",
      "features" => [
        {
          "type" => "Feature",
          "properties" => { "name" => "Gaza", "name_en" => "Gaza Strip", "iso_a2" => "PS", "adm0_a3" => "PSE" },
          "geometry" => { "type" => "Polygon",
                          "coordinates" => [ [ [ 34.0, 31.0 ], [ 35.0, 31.0 ], [ 35.0, 32.0 ], [ 34.0, 32.0 ], [ 34.0, 31.0 ] ] ] },
        },
        {
          "type" => "Feature",
          "properties" => { "name" => "Ile-de-France", "iso_a2" => "-99", "adm0_a3" => "FRA" },
          "geometry" => { "type" => "Polygon",
                          "coordinates" => [ [ [ 2.0, 48.0 ], [ 3.0, 48.0 ], [ 3.0, 49.0 ], [ 2.0, 49.0 ], [ 2.0, 48.0 ] ] ] },
        },
      ],
    }
  end

  def district(name_key, name)
    {
      "type" => "Feature",
      "properties" => { name_key => name },
      "geometry" => { "type" => "Polygon",
                      "coordinates" => [ [ [ 34.4, 31.4 ], [ 34.6, 31.4 ], [ 34.6, 31.6 ], [ 34.4, 31.6 ], [ 34.4, 31.4 ] ] ] },
    }
  end

  def resolve(anchors, districts: [], adm2: [])
    GeographyBoundaryService.stub(:fetch, admin1) do
      RegionalDistrictBoundaryCatalog.stub(:all_features, districts) do
        GeoBoundariesService.stub(:adm2_features, adm2) do
          AnchorRegionService.features_for(anchors)
        end
      end
    end
  end

  test "falls back to the admin-1 region and skips sea anchors" do
    result = resolve([
      { id: 1, lat: 31.5, lng: 34.47 },
      { id: 2, lat: 26.56, lng: 56.27 },
      { id: 3, lat: nil, lng: nil },
    ])

    assert_equal [ 1 ], result.keys
    assert_equal "Gaza Strip", result[1]["properties"]["name"], "name_en beats name"
    assert_equal "region", result[1]["properties"]["level"]
    assert_equal "PS", result[1]["properties"]["country_code"]
    assert result[1]["geometry"].present?
  end

  test "a local district that contains the anchor beats the region" do
    result = resolve([ { id: 1, lat: 31.5, lng: 34.47 } ],
                     districts: [ district("name", "Gaza City") ])

    assert_equal "Gaza City", result[1]["properties"]["name"]
    assert_equal "district", result[1]["properties"]["level"]
    assert_equal "PS", result[1]["properties"]["country_code"], "the country stays the admin-1 verdict"
  end

  test "geoBoundaries ADM2 fills in where no local district file exists" do
    result = resolve([ { id: 1, lat: 31.5, lng: 34.47 } ],
                     adm2: [ district("shapeName", "Gaza Governorate") ])

    assert_equal "Gaza Governorate", result[1]["properties"]["name"]
    assert_equal "district", result[1]["properties"]["level"]
  end

  test "a district larger than the region loses to it" do
    oversized = district("shapeName", "Piemonte-sized blob")
    oversized["geometry"]["coordinates"] = [ [ [ 30.0, 28.0 ], [ 39.0, 28.0 ], [ 39.0, 35.0 ], [ 30.0, 35.0 ], [ 30.0, 28.0 ] ] ]
    result = resolve([ { id: 1, lat: 31.5, lng: 34.47 } ], adm2: [ oversized ])

    assert_equal "Gaza Strip", result[1]["properties"]["name"],
      "precision means the smallest containing shape, not the district rung"
    assert_equal "region", result[1]["properties"]["level"]
  end

  test "a district set with no containing shape still resolves the region" do
    off_anchor = district("shapeName", "Rafah")
    off_anchor["geometry"]["coordinates"] = [ [ [ 34.2, 31.2 ], [ 34.3, 31.2 ], [ 34.3, 31.3 ], [ 34.2, 31.3 ], [ 34.2, 31.2 ] ] ]
    result = resolve([ { id: 1, lat: 31.5, lng: 34.47 } ], adm2: [ off_anchor ])

    assert_equal "Gaza Strip", result[1]["properties"]["name"]
    assert_equal "region", result[1]["properties"]["level"]
  end

  test "a -99 iso_a2 falls back to the alpha-3 code the boundary filter also accepts" do
    code = GeographyBoundaryService.stub(:fetch, admin1) do
      RegionalDistrictBoundaryCatalog.stub(:all_features, []) do
        GeoBoundariesService.stub(:adm2_features, []) do
          AnchorRegionService.country_code_for(lat: 48.5, lng: 2.5)
        end
      end
    end

    assert_equal "FRA", code
  end

  test "an unavailable dataset resolves nothing rather than raising" do
    result = GeographyBoundaryService.stub(:fetch, nil) do
      AnchorRegionService.features_for([ { id: 1, lat: 31.5, lng: 34.47 } ])
    end

    assert_empty result
  end
end
