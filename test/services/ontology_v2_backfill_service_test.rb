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

  test "group_for resolves a stage to its group" do
    assert_equal "reference", OntologyV2BackfillService.group_for("asset_airports")
    assert_equal "live", OntologyV2BackfillService.group_for("event_graph")
    assert_nil OntologyV2BackfillService.group_for("not_a_stage")
  end
end
