class RefreshOntologyRelationshipsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "derived-ontology-relationships", poll_type: "ontology"

  # This job runs many heavy DB queries and can take 250s+, blocking Sidekiq threads.
  # Cap it so it doesn't starve fast_live jobs.
  JOB_TIMEOUT = 120.seconds

  def perform
    Timeout.timeout(JOB_TIMEOUT) do
      OntologyRelationshipSyncService.sync_recent
    end
  rescue Timeout::Error
    Rails.logger.warn("[RefreshOntologyRelationshipsJob] Timed out after #{JOB_TIMEOUT}s")
  end
end
