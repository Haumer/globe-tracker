class OntologyV2BackfillJob < ApplicationJob
  queue_as :background
  tracks_polling(
    source: ->(_job, arguments) {
      options = arguments.first || {}
      stage = options.respond_to?(:[]) ? (options[:stage] || options["stage"]) : nil
      # The scheduled kickoff carries no arguments and starts at the first
      # stage, so label it that rather than "unknown".
      "ontology-v2-backfill:#{stage.presence || OntologyV2BackfillService::STAGES.first}"
    },
    poll_type: "ontology"
  )

  JOB_TIMEOUT = 110.seconds
  DEFAULT_BATCH_SIZE = 500

  # Takes a positional options hash so the poller, which enqueues with
  # `perform_later(*args)`, can start a chain at a chosen stage. Ruby folds
  # keyword-style calls into the same hash, so `perform_now(stage: "...")`
  # keeps working.
  def perform(options = {})
    options = (options || {}).symbolize_keys
    stage = options[:stage].presence || OntologyV2BackfillService::STAGES.first
    cursor = options[:cursor]
    batch_size = options[:batch_size] || DEFAULT_BATCH_SIZE

    result = Timeout.timeout(JOB_TIMEOUT) do
      OntologyV2BackfillService.run(stage: stage, cursor: cursor, batch_size: batch_size)
    end
    enqueue_next_batch(result, batch_size: batch_size)
    result
  rescue Timeout::Error
    Rails.logger.warn("[OntologyV2BackfillJob] Timed out after #{JOB_TIMEOUT}s at stage=#{stage} cursor=#{cursor}")
    record_timeout(stage: stage, cursor: cursor)
    # Raise rather than return. Polling telemetry marks a failure only when a
    # job raises, so swallowing this would report success for a stage that did
    # nothing -- and it also drops the chain, since the next batch is only
    # enqueued on the success path. Re-running resumes from the same cursor.
    raise
  end

  private

  def enqueue_next_batch(result, batch_size:)
    if result[:complete]
      next_stage = result[:next_stage]
      self.class.perform_later({ stage: next_stage, cursor: nil, batch_size: batch_size }) if next_stage.present?
    elsif result[:next_cursor].present?
      self.class.perform_later({ stage: result[:stage], cursor: result[:next_cursor], batch_size: batch_size })
    end
  end

  def record_timeout(stage:, cursor:)
    SourceFeedStatusRecorder.record(
      provider: OntologyV2BackfillService::PROVIDER,
      display_name: "Ontology v2 #{stage.to_s.tr("_", " ")}",
      feed_kind: OntologyV2BackfillService::FEED_KIND,
      endpoint_url: "ontology-v2://#{stage}",
      status: "error",
      error_message: "Timed out after #{JOB_TIMEOUT}s at cursor=#{cursor}",
      metadata: { stage: stage, cursor: cursor, timeout_seconds: JOB_TIMEOUT.to_i }.compact
    )
  end
end
