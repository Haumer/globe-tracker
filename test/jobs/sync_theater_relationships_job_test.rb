require "test_helper"

class SyncTheaterRelationshipsJobTest < ActiveJob::TestCase
  test "calls OntologyRelationshipSyncService.sync_theater_relationships" do
    called = false

    OntologyRelationshipSyncService.stub(:sync_theater_relationships, -> { called = true; {} }) do
      SyncTheaterRelationshipsJob.perform_now
    end

    assert called
  end

  test "records a failed poll when the sync raises" do
    PollingStat.where(source: "ontology-relationships:theaters").delete_all

    OntologyRelationshipSyncService.stub(:sync_theater_relationships, -> { raise "boom" }) do
      assert_raises(RuntimeError) { SyncTheaterRelationshipsJob.perform_now }
    end

    stat = PollingStat.where(source: "ontology-relationships:theaters").order(created_at: :desc).first
    assert_equal "error", stat.status, "a failing sync must not report success"
  end
end
