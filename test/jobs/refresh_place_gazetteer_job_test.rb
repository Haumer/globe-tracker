require "test_helper"

class RefreshPlaceGazetteerJobTest < ActiveSupport::TestCase
  test "tracks polling metadata" do
    assert_equal "background", RefreshPlaceGazetteerJob.new.queue_name
    assert_equal "place-gazetteer", RefreshPlaceGazetteerJob.polling_source_resolver
    assert_equal "static_places", RefreshPlaceGazetteerJob.polling_type_resolver
  end

  test "performs refresh" do
    RefreshPlaceGazetteerJob.perform_now

    assert_operator Place.count, :>, 500
  end
end
