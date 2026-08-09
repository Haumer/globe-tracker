require "test_helper"

class OntologyV2BackfillServiceTest < ActiveSupport::TestCase
  test "every stage belongs to exactly one group" do
    grouped = OntologyV2BackfillService::STAGE_GROUPS.values.flatten

    assert_equal OntologyV2BackfillService::STAGES.sort, grouped.sort
    assert_equal grouped.uniq.size, grouped.size, "a stage may not appear in two groups"
  end

  # The load-bearing property: a chain ends at its group boundary. Without this
  # the live stages queue behind ~56,000 rows of static reference data, which is
  # how everything downstream of the asset sweep went unrun for three weeks.
  test "the reference chain stops at its group boundary instead of running into live stages" do
    service = OntologyV2BackfillService.new

    last_reference = OntologyV2BackfillService::STAGE_GROUPS.fetch("reference").last
    assert_nil service.send(:next_stage_after, last_reference)
  end

  test "the live chain stops at its own boundary" do
    service = OntologyV2BackfillService.new

    last_live = OntologyV2BackfillService::STAGE_GROUPS.fetch("live").last
    assert_nil service.send(:next_stage_after, last_live)
  end

  test "chaining advances within a group" do
    service = OntologyV2BackfillService.new
    reference = OntologyV2BackfillService::STAGE_GROUPS.fetch("reference")

    assert_equal reference.second, service.send(:next_stage_after, reference.first)
    assert_equal "infrastructure_impact", service.send(:next_stage_after, "event_graph")
  end

  # The live pass must never fall back to sweeping the whole event table: at a
  # five-minute cadence that pass takes ~43 minutes on production volumes and
  # overlaps itself, with three writers already sharing the same rows.
  test "the live event graph stage is windowed to recently changed events" do
    captured = nil
    stub = ->(**opts) {
      captured = opts
      { records_fetched: 0, records_stored: 0, complete: true }
    }

    OntologyV2EventGraphService.stub(:sync_batch, stub) do
      OntologyV2BackfillService.run(stage: "event_graph", batch_size: 500)
    end

    assert captured[:updated_after].present?, "live pass must constrain by updated_at"
    assert_in_delta OntologyV2BackfillService::LIVE_EVENT_WINDOW.ago.to_i, captured[:updated_after].to_i, 60
  end

  test "the full event graph stage sweeps without a window" do
    captured = :unset
    stub = ->(**opts) {
      captured = opts[:updated_after]
      { records_fetched: 0, records_stored: 0, complete: true }
    }

    OntologyV2EventGraphService.stub(:sync_batch, stub) do
      OntologyV2BackfillService.run(stage: "event_graph_full", batch_size: 500)
    end

    assert_nil captured, "the periodic full sweep must not be windowed"
  end

  test "the windowed and full event graph passes sit on different chains" do
    assert_equal "live", OntologyV2BackfillService.group_for("event_graph")
    assert_equal "reference", OntologyV2BackfillService.group_for("event_graph_full")
  end

  test "group_for resolves a stage to its group" do
    assert_equal "reference", OntologyV2BackfillService.group_for("asset_airports")
    assert_equal "live", OntologyV2BackfillService.group_for("event_graph")
    assert_nil OntologyV2BackfillService.group_for("not_a_stage")
  end
end
