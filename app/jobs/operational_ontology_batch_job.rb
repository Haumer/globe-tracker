class OperationalOntologyBatchJob < ApplicationJob
  queue_as :background
  tracks_polling source: ->(_job, args) { "operational-ontology:#{args.first}" }, poll_type: "ontology"

  def perform(target, options = {})
    normalized_options = options.to_h.deep_symbolize_keys
    result = OperationalOntologySyncService.sync_batch(target, **normalized_options)

    if result[:records_stored].to_i.positive?
      BackgroundRefreshScheduler.enqueue_once(
        RefreshInsightsSnapshotJob,
        key: "snapshot:insights:global",
        ttl: 1.minute
      )
    end

    if result[:next_cursor]
      self.class.perform_later(
        target,
        {
          "cursor" => result[:next_cursor],
          "batch_size" => result[:batch_size],
          "updated_after" => result[:updated_after],
        }.compact
      )
    end

    result
  end
end
