require "test_helper"

class AreaReportSnapshotServiceTest < ActiveSupport::TestCase
  setup do
    @bounds = { lamin: 48.0, lamax: 49.0, lomin: 16.0, lomax: 17.0 }
  end

  test "normalize_bounds rounds coordinates to one decimal" do
    bounds = { lamin: 48.123, lamax: 49.456, lomin: 16.789, lomax: 17.012 }
    result = AreaReportSnapshotService.normalize_bounds(bounds)

    assert_equal 48.1, result[:lamin]
    assert_equal 49.5, result[:lamax]
    assert_equal 16.8, result[:lomin]
    assert_equal 17.0, result[:lomax]
  end

  test "normalize_bounds coerces string values to floats" do
    bounds = { lamin: "48.5", lamax: "49.5", lomin: "16.5", lomax: "17.5" }
    result = AreaReportSnapshotService.normalize_bounds(bounds)

    assert_equal 48.5, result[:lamin]
    assert_equal 49.5, result[:lamax]
  end

  test "scope_key_for returns deterministic key" do
    key = AreaReportSnapshotService.scope_key_for(@bounds)

    assert_equal "bbox:48.0,49.0,16.0,17.0", key
  end

  test "scope_key_for normalizes bounds before generating key" do
    bounds = { lamin: 48.123, lamax: 49.456, lomin: 16.789, lomax: 17.012 }
    key = AreaReportSnapshotService.scope_key_for(bounds)

    assert_equal "bbox:48.1,49.5,16.8,17.0", key
  end

  test "fetch delegates to LayerSnapshotStore" do
    snapshot = LayerSnapshotStore.persist(
      snapshot_type: "area_report",
      scope_key: AreaReportSnapshotService.scope_key_for(@bounds),
      payload: { test: true },
      expires_in: 5.minutes,
    )

    result = AreaReportSnapshotService.fetch(@bounds)

    assert_equal snapshot.id, result.id
    assert_equal "area_report", result.snapshot_type
  end

  test "fetch returns nil when no snapshot exists" do
    result = AreaReportSnapshotService.fetch(lamin: 0, lamax: 1, lomin: 0, lomax: 1)

    assert_nil result
  end

  test "refresh persists snapshot via LayerSnapshotStore" do
    mock_payload = { headlines: ["Test headline"] }
    AreaReport.stub(:generate, mock_payload) do
      result = AreaReportSnapshotService.refresh(@bounds)

      assert_equal "area_report", result.snapshot_type
      assert_equal "ready", result.status
      assert_equal mock_payload.deep_stringify_keys, result.payload
    end
  end

  test "refresh persists error on failure and re-raises" do
    AreaReport.stub(:generate, ->(_) { raise StandardError, "boom" }) do
      assert_raises(StandardError) do
        AreaReportSnapshotService.refresh(@bounds)
      end

      scope_key = AreaReportSnapshotService.scope_key_for(@bounds)
      snapshot = LayerSnapshotStore.fetch(snapshot_type: "area_report", scope_key: scope_key)
      assert_equal "error", snapshot.status
      assert_match(/boom/, snapshot.error_code)
    end
  end

  test "SNAPSHOT_TYPE is area_report" do
    assert_equal "area_report", AreaReportSnapshotService::SNAPSHOT_TYPE
  end
end
