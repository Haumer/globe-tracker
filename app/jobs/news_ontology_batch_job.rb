class NewsOntologyBatchJob < ApplicationJob
  queue_as :background
  tracks_polling source: ->(_job, args) { "news-ontology:#{args.first}" }, poll_type: "ontology"

  def perform(target, options = {})
    normalized_options = options.to_h.deep_symbolize_keys
    result = NewsOntologySyncService.sync_batch(target, **normalized_options)

    if result[:next_cursor]
      self.class.perform_later(
        target,
        {
          "cursor" => result[:next_cursor],
          "batch_size" => result[:batch_size],
        }
      )
    end

    result
  end
end
