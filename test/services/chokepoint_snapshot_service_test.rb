require "test_helper"

class ChokepointSnapshotServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "SNAPSHOT_TYPE is chokepoints" do
    assert_equal "chokepoints", ChokepointSnapshotService::SNAPSHOT_TYPE
  end

  test "SCOPE_KEY is global" do
    assert_equal "global", ChokepointSnapshotService::SCOPE_KEY
  end

  test "empty_payload returns hash with empty chokepoints array" do
    result = ChokepointSnapshotService.empty_payload

    assert_equal({ chokepoints: [] }, result)
  end

  test "fetch_or_enqueue returns fresh snapshot without enqueuing" do
    snapshot = LayerSnapshotStore.persist(
      snapshot_type: "chokepoints",
      scope_key: "global",
      payload: { chokepoints: [{ name: "Suez" }] },
      expires_in: 15.minutes,
    )

    result = ChokepointSnapshotService.fetch_or_enqueue

    assert_equal snapshot.id, result.id
    assert_enqueued_jobs 0
  end

  test "fetch_or_enqueue enqueues refresh for stale snapshot" do
    snapshot = LayerSnapshotStore.persist(
      snapshot_type: "chokepoints",
      scope_key: "global",
      payload: { chokepoints: [] },
      expires_in: 0.seconds,
      fetched_at: 20.minutes.ago,
    )

    result = ChokepointSnapshotService.fetch_or_enqueue

    assert_equal snapshot.id, result.id
  end

  test "fetch_or_enqueue enqueues refresh when no snapshot exists" do
    result = ChokepointSnapshotService.fetch_or_enqueue

    assert_nil result
  end

  test "refresh persists chokepoint data" do
    mock_data = [{ name: "Suez Canal", status: "open" }]
    ChokepointMonitorService.stub(:invalidate, nil) do
      ChokepointMonitorService.stub(:analyze, mock_data) do
        result = ChokepointSnapshotService.refresh

        assert_equal "chokepoints", result.snapshot_type
        assert_equal "ready", result.status
        assert_equal({ "chokepoints" => mock_data.map(&:deep_stringify_keys) }, result.payload)
      end
    end
  end

  test "refresh persists error on failure and re-raises" do
    ChokepointMonitorService.stub(:invalidate, nil) do
      ChokepointMonitorService.stub(:analyze, -> { raise StandardError, "fail" }) do
        assert_raises(StandardError) do
          ChokepointSnapshotService.refresh
        end

        snapshot = LayerSnapshotStore.fetch(snapshot_type: "chokepoints", scope_key: "global")
        assert_equal "error", snapshot.status
        assert_match(/fail/, snapshot.error_code)
      end
    end
  end
end
