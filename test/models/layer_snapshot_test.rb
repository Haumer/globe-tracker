require "test_helper"

class LayerSnapshotTest < ActiveSupport::TestCase
  setup do
    @snapshot = LayerSnapshot.create!(
      snapshot_type: "earthquakes",
      scope_key: "global",
      status: "ready",
      payload: { count: 42 },
      expires_at: 1.hour.from_now
    )
  end

  test "valid creation" do
    assert @snapshot.persisted?
  end

  test "snapshot_type is required" do
    r = LayerSnapshot.new(scope_key: "global", status: "ready")
    assert_not r.valid?
    assert_includes r.errors[:snapshot_type], "can't be blank"
  end

  test "scope_key is required" do
    r = LayerSnapshot.new(snapshot_type: "earthquakes", scope_key: "", status: "ready")
    assert_not r.valid?
    assert_includes r.errors[:scope_key], "can't be blank"
  end

  test "status must be valid" do
    r = LayerSnapshot.new(snapshot_type: "earthquakes", scope_key: "global", status: "invalid")
    assert_not r.valid?
    assert r.errors[:status].any?
  end

  test "fresh? returns true when not expired" do
    assert @snapshot.fresh?
  end

  test "fresh? returns false when expired" do
    @snapshot.update!(expires_at: 1.hour.ago)
    assert_not @snapshot.fresh?
  end

  test "fresh? returns false when nil" do
    @snapshot.update!(expires_at: nil)
    assert_not @snapshot.fresh?
  end

  test "pending? returns true when status is pending" do
    @snapshot.status = "pending"
    assert @snapshot.pending?
  end

  test "pending? returns false for ready" do
    assert_not @snapshot.pending?
  end

  test "for_snapshot scope filters by type and key" do
    other = LayerSnapshot.create!(snapshot_type: "flights", scope_key: "us", status: "ready")
    results = LayerSnapshot.for_snapshot("earthquakes", "global")
    assert_includes results, @snapshot
    assert_not_includes results, other
  end

  test "for_snapshot scope defaults to global" do
    results = LayerSnapshot.for_snapshot("earthquakes")
    assert_includes results, @snapshot
  end
end
