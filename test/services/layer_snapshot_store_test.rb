require "test_helper"

class LayerSnapshotStoreTest < ActiveSupport::TestCase
  test "persist creates a new snapshot" do
    result = LayerSnapshotStore.persist(
      snapshot_type: "test_layer",
      scope_key: "global",
      payload: { items: [1, 2, 3] },
      expires_in: 10.minutes,
    )

    assert_not_nil result
    assert_equal "test_layer", result.snapshot_type
    assert_equal "global", result.scope_key
    assert_equal "ready", result.status
    assert_nil result.error_code
    assert_equal({ "items" => [1, 2, 3] }, result.payload)
    assert result.fresh?
  end

  test "persist updates existing snapshot" do
    LayerSnapshotStore.persist(
      snapshot_type: "test_update",
      scope_key: "global",
      payload: { version: 1 },
      expires_in: 10.minutes,
    )

    result = LayerSnapshotStore.persist(
      snapshot_type: "test_update",
      scope_key: "global",
      payload: { version: 2 },
      expires_in: 10.minutes,
    )

    assert_equal({ "version" => 2 }, result.payload)
    assert_equal 1, LayerSnapshot.where(snapshot_type: "test_update", scope_key: "global").count
  end

  test "persist clears error state" do
    LayerSnapshotStore.persist_error(
      snapshot_type: "test_clear",
      scope_key: "global",
      error_code: "failed",
      expires_in: 1.minute,
    )

    result = LayerSnapshotStore.persist(
      snapshot_type: "test_clear",
      scope_key: "global",
      payload: { ok: true },
      expires_in: 10.minutes,
    )

    assert_equal "ready", result.status
    assert_nil result.error_code
  end

  test "persist uses default scope_key of global" do
    result = LayerSnapshotStore.persist(
      snapshot_type: "test_default_scope",
      payload: { data: true },
      expires_in: 5.minutes,
    )

    assert_equal "global", result.scope_key
  end

  test "persist stores metadata" do
    result = LayerSnapshotStore.persist(
      snapshot_type: "test_meta",
      scope_key: "custom",
      payload: {},
      metadata: { source: "test" },
      expires_in: 5.minutes,
    )

    assert_equal({ "source" => "test" }, result.metadata)
  end

  test "fetch returns snapshot by type and scope" do
    LayerSnapshotStore.persist(
      snapshot_type: "test_fetch",
      scope_key: "region_a",
      payload: { found: true },
      expires_in: 5.minutes,
    )

    result = LayerSnapshotStore.fetch(snapshot_type: "test_fetch", scope_key: "region_a")

    assert_not_nil result
    assert_equal({ "found" => true }, result.payload)
  end

  test "fetch returns nil when not found" do
    result = LayerSnapshotStore.fetch(snapshot_type: "nonexistent", scope_key: "global")

    assert_nil result
  end

  test "persist_error creates error snapshot" do
    result = LayerSnapshotStore.persist_error(
      snapshot_type: "test_error",
      scope_key: "global",
      error_code: "timeout occurred",
      expires_in: 2.minutes,
    )

    assert_equal "error", result.status
    assert_equal "timeout occurred", result.error_code
  end

  test "persist_error merges metadata on existing snapshot" do
    LayerSnapshotStore.persist(
      snapshot_type: "test_merge",
      scope_key: "global",
      payload: { old: true },
      metadata: { first: "value" },
      expires_in: 5.minutes,
    )

    result = LayerSnapshotStore.persist_error(
      snapshot_type: "test_merge",
      scope_key: "global",
      error_code: "boom",
      metadata: { second: "value" },
      expires_in: 1.minute,
    )

    assert_equal "error", result.status
    assert_equal "value", result.metadata["first"]
    assert_equal "value", result.metadata["second"]
  end

  test "persist_error truncates long error codes" do
    long_error = "x" * 500
    result = LayerSnapshotStore.persist_error(
      snapshot_type: "test_truncate",
      scope_key: "global",
      error_code: long_error,
      expires_in: 1.minute,
    )

    assert result.error_code.length <= 255
  end

  test "persist sets empty hash for nil payload" do
    result = LayerSnapshotStore.persist(
      snapshot_type: "test_nil_payload",
      scope_key: "global",
      payload: nil,
      expires_in: 5.minutes,
    )

    assert_equal({}, result.payload)
  end
end
