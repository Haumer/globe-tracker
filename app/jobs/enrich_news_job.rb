class EnrichNewsJob < ApplicationJob
  queue_as :default

  def perform
    NewsEnrichmentService.enrich_recent(limit: 100)
  end
end
