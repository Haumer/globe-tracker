class SyncNewsRegistryLinksJob < ApplicationJob
  queue_as :background
  tracks_polling source: "ontology-relationships:news-registry", poll_type: "ontology"

  # Cluster -> registry entity edges (names_entity), previously rake-only.
  #
  # The window is four days rather than the rake default of 21 because the
  # window is what bounds spend: the deterministic tier is free, but the
  # resolver tier re-asks the model about every still-ambiguous cluster in
  # scope on every run. Four days still covers a weekend poller outage, and at
  # this cadence the resolver cost stays in the tens of calls per day.
  #
  # Always runs with the resolver. A resolver-less run is not a cheaper version
  # of the same thing: write_edges reconciles each cluster's edges against what
  # this run matched, so running deterministic-only on a schedule would prune
  # the edges a resolver run wrote.
  WINDOW_DAYS = 4

  def perform
    NewsRegistryLinkService.sync_recent(days: WINDOW_DAYS)
  end
end
