require "test_helper"

class RefreshOntologyRelationshipsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshOntologyRelationshipsJob.new.queue_name
  end

  test "tracks polling with source derived-ontology-relationships and poll_type ontology" do
    assert_equal "derived-ontology-relationships", RefreshOntologyRelationshipsJob.polling_source_resolver
    assert_equal "ontology", RefreshOntologyRelationshipsJob.polling_type_resolver
  end

  test "calls OntologyRelationshipSyncService.sync_recent" do
    called = false
    OntologyRelationshipSyncService.stub(:sync_recent, -> { called = true; 4 }) do
      RefreshOntologyRelationshipsJob.perform_now
    end
    assert called
  end
end
