require "test_helper"

class AreaSummaryServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "area-summary-test@example.com", password: "password123456")
    @workspace = AreaWorkspace.create!(
      user: @user,
      name: "Test workspace",
      scope_type: "bbox",
      profile: "general",
      bounds: { lamin: 48.0, lamax: 49.0, lomin: 16.0, lomax: 17.0 },
    )
    @service = AreaSummaryService.new(@workspace)
  end

  test "call returns expected top-level keys" do
    # Stub snapshot services to avoid DB lookups on missing snapshots
    InsightSnapshotService.stub(:fetch_or_enqueue, nil) do
      ConflictPulseSnapshotService.stub(:fetch_or_enqueue, nil) do
        ChokepointSnapshotService.stub(:fetch_or_enqueue, nil) do
          result = @service.call

          assert result.key?(:brief)
          assert result.key?(:overview)
          assert result.key?(:signals)
          assert result.key?(:movement)
          assert result.key?(:assets)
          assert result.key?(:infrastructure)
          assert result.key?(:impacts)
          assert result.key?(:snapshots)
        end
      end
    end
  end

  test "SEVERITY_ORDER maps severity levels to numeric order" do
    assert_equal 0, AreaSummaryService::SEVERITY_ORDER["critical"]
    assert_equal 1, AreaSummaryService::SEVERITY_ORDER["high"]
    assert_equal 2, AreaSummaryService::SEVERITY_ORDER["medium"]
    assert_equal 3, AreaSummaryService::SEVERITY_ORDER["low"]
  end

  test "point_in_bounds? returns true for point inside bounds" do
    result = @service.send(:point_in_bounds?, 48.5, 16.5)

    assert result
  end

  test "point_in_bounds? returns false for point outside bounds" do
    result = @service.send(:point_in_bounds?, 50.0, 16.5)

    refute result
  end

  test "point_in_bounds? returns false for nil coordinates" do
    refute @service.send(:point_in_bounds?, nil, 16.5)
    refute @service.send(:point_in_bounds?, 48.5, nil)
    refute @service.send(:point_in_bounds?, nil, nil)
  end

  test "value_for reads from hash with symbol key" do
    obj = { name: "test" }
    assert_equal "test", @service.send(:value_for, obj, :name)
  end

  test "value_for reads from hash with string key" do
    obj = { "name" => "test" }
    assert_equal "test", @service.send(:value_for, obj, :name)
  end

  test "value_for returns nil for non-hash" do
    assert_nil @service.send(:value_for, nil, :name)
  end

  test "parse_time handles valid time string" do
    result = @service.send(:parse_time, "2025-01-15T12:00:00Z")

    assert_kind_of Time, result
  end

  test "parse_time returns nil for blank" do
    assert_nil @service.send(:parse_time, nil)
    assert_nil @service.send(:parse_time, "")
  end

  test "parse_time returns nil for invalid string" do
    assert_nil @service.send(:parse_time, "not-a-time")
  end

  test "snapshot_status_for returns pending for nil snapshot" do
    assert_equal "pending", @service.send(:snapshot_status_for, nil)
  end

  test "snapshot_status_for returns ready for fresh ready snapshot" do
    snapshot = LayerSnapshotStore.persist(
      snapshot_type: "test_summary",
      scope_key: "global",
      payload: {},
      expires_in: 10.minutes,
    )
    assert_equal "ready", @service.send(:snapshot_status_for, snapshot)
  end

  test "snapshot_status_for returns error for error snapshot" do
    snapshot = LayerSnapshotStore.persist_error(
      snapshot_type: "test_summary_err",
      scope_key: "global",
      error_code: "boom",
      expires_in: 10.minutes,
    )
    assert_equal "error", @service.send(:snapshot_status_for, snapshot)
  end
end
