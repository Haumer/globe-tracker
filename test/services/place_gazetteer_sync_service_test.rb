require "test_helper"

class PlaceGazetteerSyncServiceTest < ActiveSupport::TestCase
  test "refresh imports global and enriched places with aliases" do
    count = PlaceGazetteerSyncService.refresh

    assert_operator count, :>, 500
    london = Place.lookup("London").first
    assert_equal "London", london.name
    assert_equal "gb", london.country_code
    assert_operator london.importance_score, :>, 0.9

    vienna = Place.lookup("Wien", country_code: "at").first
    assert_equal "Vienna", vienna.name
    assert_equal "city_profile", vienna.source
    assert_equal "at", vienna.country_code
    assert_equal "AUT", vienna.metadata["country_code_alpha3"]
  end

  test "refresh is idempotent" do
    PlaceGazetteerSyncService.refresh
    first_count = Place.count
    first_alias_count = PlaceAlias.count

    PlaceGazetteerSyncService.refresh

    assert_equal first_count, Place.count
    assert_equal first_alias_count, PlaceAlias.count
  end
end
