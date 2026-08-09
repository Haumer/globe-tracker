require "test_helper"

class SyncHazardRelationshipsJobTest < ActiveJob::TestCase
  test "calls OntologyRelationshipSyncService.sync_hazard_relationships" do
    called = false

    OntologyRelationshipSyncService.stub(:sync_hazard_relationships, -> { called = true; {} }) do
      SyncHazardRelationshipsJob.perform_now
    end

    assert called
  end

  test "records a failed poll when the sync raises" do
    PollingStat.where(source: "ontology-relationships:hazards").delete_all

    OntologyRelationshipSyncService.stub(:sync_hazard_relationships, -> { raise "boom" }) do
      assert_raises(RuntimeError) { SyncHazardRelationshipsJob.perform_now }
    end

    stat = PollingStat.where(source: "ontology-relationships:hazards").order(created_at: :desc).first
    assert_equal "error", stat.status, "a failing sync must not report success"
  end

  test "reports its own polling source rather than sharing one with other derivations" do
    PollingStat.where(source: "ontology-relationships:hazards").delete_all

    OntologyRelationshipSyncService.stub(:sync_hazard_relationships, -> { {} }) do
      SyncHazardRelationshipsJob.perform_now
    end

    assert_equal 1, PollingStat.where(source: "ontology-relationships:hazards", status: "success").count
  end
end
