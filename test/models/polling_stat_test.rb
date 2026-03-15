require "test_helper"

class PollingStatTest < ActiveSupport::TestCase
  test "creation with required fields" do
    stat = PollingStat.create!(
      source: "opensky",
      poll_type: "flights",
      records_fetched: 100,
      records_stored: 95,
      duration_ms: 1500,
      status: "success"
    )
    assert stat.persisted?
  end

  test "recent scope returns stats from last hour" do
    PollingStat.create!(source: "opensky", poll_type: "flights", status: "success", created_at: 30.minutes.ago)
    PollingStat.create!(source: "opensky", poll_type: "flights", status: "success", created_at: 2.hours.ago)

    assert_equal 1, PollingStat.recent.count
  end

  test "by_source scope filters by source" do
    PollingStat.create!(source: "opensky", poll_type: "flights", status: "success")
    PollingStat.create!(source: "usgs", poll_type: "earthquakes", status: "success")

    assert_equal 1, PollingStat.by_source("opensky").count
  end

  test "successful and failed scopes" do
    PollingStat.create!(source: "opensky", poll_type: "flights", status: "success")
    PollingStat.create!(source: "usgs", poll_type: "earthquakes", status: "error", error_message: "timeout")

    assert_equal 1, PollingStat.successful.count
    assert_equal 1, PollingStat.failed.count
  end
end
