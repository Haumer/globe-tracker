require "test_helper"

class ConflictPulseSnapshotServiceTest < ActiveSupport::TestCase
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

  test "SNAPSHOT_TYPE is conflict_pulse" do
    assert_equal "conflict_pulse", ConflictPulseSnapshotService::SNAPSHOT_TYPE
  end

  test "SCOPE_KEY is global" do
    assert_equal "global", ConflictPulseSnapshotService::SCOPE_KEY
  end

  test "empty_payload returns expected structure" do
    result = ConflictPulseSnapshotService.empty_payload

    assert_equal [], result[:zones]
    assert_equal [], result[:strategic_situations]
    assert_equal [], result[:strike_arcs]
    assert_equal [], result[:hex_cells]
  end

  test "fetch_or_enqueue returns fresh snapshot without enqueuing" do
    snapshot = LayerSnapshotStore.persist(
      snapshot_type: "conflict_pulse",
      scope_key: "global",
      payload: { zones: [{ name: "Zone A" }] },
      expires_in: 5.minutes,
    )

    result = ConflictPulseSnapshotService.fetch_or_enqueue

    assert_equal snapshot.id, result.id
    assert_enqueued_jobs 0
  end

  test "fetch_or_enqueue returns nil when no snapshot exists" do
    result = ConflictPulseSnapshotService.fetch_or_enqueue

    assert_nil result
  end

  test "refresh persists conflict pulse data" do
    mock_data = { zones: [{ name: "Test" }], strategic_situations: [], strike_arcs: [], hex_cells: [] }
    ConflictPulseService.stub(:invalidate, nil) do
      ConflictPulseService.stub(:analyze, mock_data) do
        result = ConflictPulseSnapshotService.refresh

        assert_equal "conflict_pulse", result.snapshot_type
        assert_equal "ready", result.status
      end
    end
  end

  test "refresh persists error on failure and re-raises" do
    ConflictPulseService.stub(:invalidate, nil) do
      ConflictPulseService.stub(:analyze, -> { raise StandardError, "analysis failed" }) do
        assert_raises(StandardError) do
          ConflictPulseSnapshotService.refresh
        end

        snapshot = LayerSnapshotStore.fetch(snapshot_type: "conflict_pulse", scope_key: "global")
        assert_equal "error", snapshot.status
        assert_match(/analysis failed/, snapshot.error_code)
      end
    end
  end
end
