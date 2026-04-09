require "test_helper"

class PollingStatRecorderTest < ActiveSupport::TestCase
  test "record creates a polling stat" do
    assert_difference "PollingStat.count" do
      PollingStatRecorder.record(
        source: "adsb",
        poll_type: "refresh",
        status: "success",
        records_fetched: 100,
        records_stored: 95,
        duration_ms: 1500,
      )
    end

    stat = PollingStat.last
    assert_equal "adsb", stat.source
    assert_equal "refresh", stat.poll_type
    assert_equal "success", stat.status
    assert_equal 100, stat.records_fetched
    assert_equal 95, stat.records_stored
    assert_equal 1500, stat.duration_ms
  end

  test "record uses records_fetched as records_stored when not specified" do
    PollingStatRecorder.record(
      source: "opensky",
      poll_type: "refresh",
      status: "success",
      records_fetched: 50,
    )

    stat = PollingStat.last
    assert_equal 50, stat.records_stored
  end

  test "record stores error_message" do
    PollingStatRecorder.record(
      source: "adsb",
      poll_type: "refresh",
      status: "error",
      error_message: "Connection timed out",
    )

    stat = PollingStat.last
    assert_equal "error", stat.status
    assert_equal "Connection timed out", stat.error_message
  end

  test "record truncates long error messages" do
    long_message = "x" * 2000
    PollingStatRecorder.record(
      source: "adsb",
      poll_type: "refresh",
      status: "error",
      error_message: long_message,
    )

    stat = PollingStat.last
    assert stat.error_message.length <= 1000
  end

  test "record returns nil when source is blank" do
    result = PollingStatRecorder.record(
      source: "",
      poll_type: "refresh",
      status: "success",
    )

    assert_nil result
  end

  test "record returns nil when poll_type is blank" do
    result = PollingStatRecorder.record(
      source: "adsb",
      poll_type: "",
      status: "success",
    )

    assert_nil result
  end

  test "record converts values to correct types" do
    PollingStatRecorder.record(
      source: :adsb,
      poll_type: :refresh,
      status: :success,
      records_fetched: "42",
      duration_ms: "100",
    )

    stat = PollingStat.last
    assert_equal "adsb", stat.source
    assert_equal "refresh", stat.poll_type
    assert_equal 42, stat.records_fetched
    assert_equal 100, stat.duration_ms
  end

  test "record does not raise on DB error" do
    PollingStat.stub(:create!, ->(_) { raise ActiveRecord::RecordInvalid.new(PollingStat.new) }) do
      result = PollingStatRecorder.record(
        source: "adsb",
        poll_type: "refresh",
        status: "success",
      )

      assert_nil result
    end
  end
end
