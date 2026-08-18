class EnrichNewsJob < ApplicationJob
  queue_as :default

  # Every run was returning exactly 100 -- the old cap, not the available work,
  # so enrichment was saturated and a queue was building behind it. Ingest runs
  # ~1,300-1,800 articles/hour once the sitemap transport is warm, against the
  # 1,200/hour that 100-per-five-minutes allows. Articles past the cap reach the
  # globe geocoded by the publisher-domain fallback instead of the AI path.
  #
  # 200 gives 2,400/hour: comfortably above ingest, with the surplus draining
  # the backlog. Raising this rather than shortening the interval is deliberate
  # -- combined_enrich only marks rows enriched after its API call returns, so
  # two overlapping runs would select the same rows and pay for them twice.
  # A larger batch keeps one run per five-minute slot; a shorter interval does
  # not.
  BATCH_LIMIT = 200

  def perform
    NewsEnrichmentService.enrich_recent(limit: BATCH_LIMIT)
  end
end
