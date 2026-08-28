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

  # Enforced cooperatively: the service checks it between rows and returns
  # partial progress, rather than Timeout.timeout cutting the thread wherever
  # it happens to be. Timeout kills via Thread#raise, and an exception landing
  # inside a libpq call or while the connection-pool mutex is held can wedge
  # the whole process -- during the 2026-08-27 worker freeze this job was
  # exactly what was running. A deadline the service honors between rows can
  # only ever stop at a row boundary, and the chain resumes from the returned
  # cursor instead of being dropped.
  JOB_DEADLINE = 110.seconds
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

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + JOB_DEADLINE
    result = OntologyV2BackfillService.run(stage: stage, cursor: cursor, batch_size: batch_size, deadline: deadline)
    if result[:deadline_hit]
      Rails.logger.warn(
        "[OntologyV2BackfillJob] deadline hit at stage=#{stage} cursor=#{cursor} " \
          "after #{result[:events]} rows; chain resumes from #{result[:next_cursor]}"
      )
    end
    enqueue_next_batch(result, batch_size: batch_size)
    result
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

end
