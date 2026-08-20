require "test_helper"

class AnchorRegionServiceTest < ActiveSupport::TestCase
  # A two-region world: a square around Gaza with clean codes, and a square
  # around Paris carrying Natural Earth's "-99" iso_a2 quirk.
  def dataset
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

  test "resolves each anchor to its containing region and skips sea anchors" do
    result = GeographyBoundaryService.stub(:fetch, dataset) do
      AnchorRegionService.features_for([
        { id: 1, lat: 31.5, lng: 34.47 },
        { id: 2, lat: 26.56, lng: 56.27 },
        { id: 3, lat: nil, lng: nil },
      ])
    end

    assert_equal [ 1 ], result.keys
    assert_equal "Gaza Strip", result[1]["properties"]["name"], "name_en beats name"
    assert_equal "PS", result[1]["properties"]["country_code"]
    assert result[1]["geometry"].present?
  end

  test "a -99 iso_a2 falls back to the alpha-3 code the boundary filter also accepts" do
    code = GeographyBoundaryService.stub(:fetch, dataset) do
      AnchorRegionService.country_code_for(lat: 48.5, lng: 2.5)
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
