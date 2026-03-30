class RefreshOntologyRelationshipsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "derived-ontology-relationships", poll_type: "ontology"

  def perform
    OntologyRelationshipSyncService.sync_recent
  end
end
