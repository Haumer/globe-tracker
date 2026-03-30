require "test_helper"

class InsightSnapshotServiceTest < ActiveSupport::TestCase
  test "refresh builds insights without inline ontology relationship sync" do
    original_sync_recent = OntologyRelationshipSyncService.method(:sync_recent)
    original_analyze = CrossLayerAnalyzer.method(:analyze)

    OntologyRelationshipSyncService.singleton_class.send(:define_method, :sync_recent) do |*args, **kwargs|
      raise "sync_recent should not be called during insight refresh"
    end

    CrossLayerAnalyzer.singleton_class.send(:define_method, :analyze) do
      [{ title: "Signal", severity: "medium" }]
    end

    snapshot = InsightSnapshotService.refresh

    assert_equal "ready", snapshot.status
    assert_equal [{ "title" => "Signal", "severity" => "medium" }], snapshot.payload["insights"]
  ensure
    OntologyRelationshipSyncService.singleton_class.send(:define_method, :sync_recent, original_sync_recent)
    CrossLayerAnalyzer.singleton_class.send(:define_method, :analyze, original_analyze)
  end
end
