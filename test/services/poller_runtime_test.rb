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

  test "embedded? tracks EMBED_POLLER_IN_WORKER" do
    original = ENV["EMBED_POLLER_IN_WORKER"]

    ENV["EMBED_POLLER_IN_WORKER"] = "1"
    assert PollerRuntime.send(:embedded?)

    ENV["EMBED_POLLER_IN_WORKER"] = nil
    refute PollerRuntime.send(:embedded?)
  ensure
    ENV["EMBED_POLLER_IN_WORKER"] = original
  end

  # Regression: the handler used to call PollerRuntimeState.request_stop!, which
  # writes to the DB. Trap context forbids taking a mutex, so that raised
  # "ThreadError: can't be called from trap context" and silently killed ingest
  # (production, 2026-08-06). The handler must only set a flag.
  test "signal handler sets the stop flag without touching the database" do
    previous_int = Signal.trap("INT", "DEFAULT")
    previous_term = Signal.trap("TERM", "DEFAULT")

    PollerRuntime.instance_variable_set(:@stop_requested, false)
    PollerRuntime.send(:trap_signals)

    handler = Signal.trap("TERM", "DEFAULT")
    assert_kind_of Proc, handler

    PollerRuntimeState.stub(:request_stop!, ->(*) { flunk "handler must not hit the DB in trap context" }) do
      handler.call
    end

    assert PollerRuntime.instance_variable_get(:@stop_requested)
  ensure
    Signal.trap("INT", previous_int || "DEFAULT")
    Signal.trap("TERM", previous_term || "DEFAULT")
    PollerRuntime.instance_variable_set(:@stop_requested, false)
  end

  # Regression: Sidekiq's quiet/shutdown hooks used to call
  # PollerRuntimeState.request_stop!, persisting desired_state="stopped" globally.
  # dokku keeps the outgoing container up for 60s past the new one's boot, so the
  # old worker's shutdown switched the fresh worker's poller back off on every
  # deploy (production, 2026-08-07 23:40Z). Stopping must stay process-local.
  test "request_local_stop! sets the flag without persisting operator intent" do
    PollerRuntime.instance_variable_set(:@stop_requested, false)

    PollerRuntimeState.stub(:request_stop!, ->(*) { flunk "must not persist desired_state on process shutdown" }) do
      PollerRuntimeState.stub(:request_pause!, ->(*) { flunk "must not persist desired_state on process quiet" }) do
        PollerRuntime.request_local_stop!
      end
    end

    assert PollerRuntime.instance_variable_get(:@stop_requested)
  ensure
    PollerRuntime.instance_variable_set(:@stop_requested, false)
  end

  test "interruptible_sleep returns early once the stop flag is set" do
    PollerRuntime.instance_variable_set(:@stop_requested, true)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    PollerRuntime.send(:interruptible_sleep, 30)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 1.0
  ensure
    PollerRuntime.instance_variable_set(:@stop_requested, false)
  end
end
