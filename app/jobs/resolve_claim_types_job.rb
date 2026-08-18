# Classifies the claims the extractor could not label, or labelled wrongly.
#
# Runs every cycle rather than as a backfill because the clusterer reads
# event_family and event_type the moment an article is scored, so a claim that
# is still `general` when its cluster is decided has already missed its window.
#
# The limit is a per-cycle cost ceiling, not a backlog target. Steady state is
# roughly 1,200 in-scope articles a day -- about 4 a minute -- so 400 leaves
# ample headroom to work down a backlog without any single cycle running long
# or spending unboundedly if a feed floods.
class ResolveClaimTypesJob < ApplicationJob
  queue_as :default

  BATCH_LIMIT = 400

  def perform(limit: BATCH_LIMIT, scope: :all)
    stats = NewsClaimTypeBackfillService.run(limit: limit, scope: scope)
    return if stats[:candidates].to_i.zero?

    Rails.logger.info(
      "ResolveClaimTypesJob: considered=#{stats[:candidates]} assigned=#{stats[:assigned].to_i} " \
      "none=#{stats[:none].to_i} unreachable=#{stats[:unreachable].to_i}"
    )
  end
end
