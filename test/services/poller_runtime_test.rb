require "test_helper"

class PollerRuntimeTest < ActiveSupport::TestCase
  test "LOOP_INTERVAL matches GlobalPollerService" do
    assert_equal GlobalPollerService::LOOP_INTERVAL, PollerRuntime::LOOP_INTERVAL
  end

  test "runtime_metadata returns hash with expected keys" do
    PollerRuntimeState.stub(:status, {
      started_at: Time.current,
      last_poll_at: Time.current,
      last_tick_at: Time.current,
      poll_count: 42,
    }) do
      AisStreamService.stub(:running?, false) do
        metadata = PollerRuntime.send(:runtime_metadata)

        assert_kind_of Hash, metadata
        assert metadata.key?("started_at")
        assert metadata.key?("poll_count")
        assert metadata.key?("ais_mode")
        assert metadata.key?("ais_running")
        assert metadata.key?("scheduler")
      end
    end
  end

  test "ais_mode returns disabled when no key set" do
    original = ENV["AISSTREAM_API_KEY"]
    ENV["AISSTREAM_API_KEY"] = nil

    result = PollerRuntime.send(:ais_mode)

    assert_equal "disabled", result
  ensure
    ENV["AISSTREAM_API_KEY"] = original
  end

  test "ais_mode returns stream when key is set" do
    original = ENV["AISSTREAM_API_KEY"]
    ENV["AISSTREAM_API_KEY"] = "test-key"

    result = PollerRuntime.send(:ais_mode)

    assert_equal "stream", result
  ensure
    ENV["AISSTREAM_API_KEY"] = original
  end

  test "runtime_owner returns worker for worker dyno" do
    original = ENV["DYNO"]
    ENV["DYNO"] = "worker.1"

    result = PollerRuntime.send(:runtime_owner)

    assert_equal "worker", result
  ensure
    ENV["DYNO"] = original
  end

  test "runtime_owner returns poller for non-worker dyno" do
    original = ENV["DYNO"]
    ENV["DYNO"] = "web.1"

    result = PollerRuntime.send(:runtime_owner)

    assert_equal "poller", result
  ensure
    ENV["DYNO"] = original
  end

  test "runtime_owner returns poller when DYNO is not set" do
    original = ENV["DYNO"]
    ENV["DYNO"] = nil

    result = PollerRuntime.send(:runtime_owner)

    assert_equal "poller", result
  ensure
    ENV["DYNO"] = original
  end
end
