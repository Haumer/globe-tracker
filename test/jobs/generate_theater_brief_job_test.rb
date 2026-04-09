require "test_helper"

class GenerateTheaterBriefJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", GenerateTheaterBriefJob.new.queue_name
  end

  test "calls TheaterBriefService.refresh with scope_key and zone_payload" do
    scope_key = "europe"
    zone_payload = { "lat" => 48.0, "lon" => 11.0 }
    snapshot = OpenStruct.new(payload: { "brief" => { "key_developments" => %w[a b c] } })

    called_with = nil
    mock = ->(**kwargs) { called_with = kwargs; snapshot }

    TheaterBriefService.stub(:refresh, mock) do
      result = GenerateTheaterBriefJob.perform_now(scope_key, zone_payload)
      assert_equal({ records_fetched: 3, records_stored: 1 }, result)
    end

    assert_equal scope_key, called_with[:scope_key]
    assert_equal zone_payload, called_with[:zone_payload]
    assert_equal true, called_with[:force]
  end
end
