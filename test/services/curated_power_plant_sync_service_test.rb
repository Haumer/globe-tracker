require "test_helper"

class CuratedPowerPlantSyncServiceTest < ActiveSupport::TestCase
  test "skips unmatched curated records without coordinates" do
    record = {
      "id" => "pp-at-simmering",
      "name" => "Simmering Power Plant",
      "match_name" => "Simmering",
      "country_code" => "AUT",
    }

    CuratedPowerPlantCatalog.stub(:all, [record]) do
      assert_no_difference("PowerPlant.count") do
        result = CuratedPowerPlantSyncService.sync!

        assert_equal 0, result[:updated]
        assert_equal 0, result[:inserted]
        assert_equal 1, result[:total]
      end
    end
  end

  test "creates unmatched curated records when coordinates are present" do
    record = {
      "id" => "pp-at-synthetic-test",
      "name" => "Synthetic Test Plant",
      "country_code" => "AUT",
      "country_name" => "Austria",
      "lat" => 48.2,
      "lng" => 16.37,
    }

    CuratedPowerPlantCatalog.stub(:all, [record]) do
      assert_difference("PowerPlant.count", 1) do
        result = CuratedPowerPlantSyncService.sync!

        assert_equal 0, result[:updated]
        assert_equal 1, result[:inserted]
        assert_equal 1, result[:total]
      end
    end

    plant = PowerPlant.find_by!(gppd_idnr: "CURATED-PP-AT-SYNTHETIC-TEST")
    assert_equal "Synthetic Test Plant", plant.name
    assert_equal "AUT", plant.country_code
    assert_equal 48.2, plant.latitude
    assert_equal 16.37, plant.longitude
  end
end
