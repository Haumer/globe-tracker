require "test_helper"

class PollAdsbRegionJobTest < ActiveSupport::TestCase
  test "is assigned to the fast_live queue" do
    assert_equal "fast_live", PollAdsbRegionJob.new.queue_name
  end

  test "tracks polling with dynamic source and poll_type flights" do
    assert_equal "flights", PollAdsbRegionJob.polling_type_resolver
    resolver = PollAdsbRegionJob.polling_source_resolver
    assert_equal "adsb-europe", resolver.call(nil, ["europe", 48.0, 11.0])
  end

  test "calls AdsbService.fetch_flights with computed bounds" do
    called_with = nil
    mock = ->(**kwargs) { called_with = kwargs; %w[f1 f2] }

    AdsbService.stub(:fetch_flights, mock) do
      result = PollAdsbRegionJob.perform_now("mideast", 25.0, 55.0)
      assert_equal 2, result
    end

    bounds = called_with[:bounds]
    assert_equal 5.0, bounds[:lamin]
    assert_equal 45.0, bounds[:lamax]
    assert_equal 30.0, bounds[:lomin]
    assert_equal 80.0, bounds[:lomax]
  end

  test "skips stale job on fast_live queue" do
    job = PollAdsbRegionJob.new("mideast", 25.0, 55.0)
    job.enqueued_at = 2.minutes.ago.iso8601

    AdsbService.stub(:fetch_flights, ->(**_kw) { raise "should not be called" }) do
      result = job.perform_now
      assert_equal false, result
    end
  end
end
