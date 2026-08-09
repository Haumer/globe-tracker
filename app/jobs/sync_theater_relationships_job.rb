class SyncTheaterRelationshipsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "ontology-relationships:theaters", poll_type: "ontology"

  # Theater pressure, flow dependencies, downstream exposure and operational
  # activity -- the four derivations that share a prelude. Measured at ~11s
  # including that prelude, so it needs no timeout of its own; if it grows one,
  # it should raise rather than report success.
  def perform
    OntologyRelationshipSyncService.sync_theater_relationships
  end
end
