class SyncHazardRelationshipsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "ontology-relationships:hazards", poll_type: "ontology"

  # Fires, corroborations and label repairs. Roughly five seconds of work that
  # spent three weeks starved inside a job whose first stage took 278s, so it
  # runs on its own now. Errors are left to raise: polling telemetry records a
  # failure only when the job raises, and a rescued timeout reporting success is
  # exactly how the starvation stayed invisible.
  def perform
    OntologyRelationshipSyncService.sync_hazard_relationships
  end
end
