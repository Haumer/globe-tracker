class BuildSituationsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "situations:build", poll_type: "ontology"

  # SituationBuilder and its occurrence-link prerequisite previously ran only
  # from `rake ontology:build_situations`, so prod's situations were whatever
  # the last manual run left -- decaying as the 21-day window moved on, under a
  # UI that now opens on them.
  #
  # Chained in one job on purpose: the builder keys hazard members off the
  # edges the occurrence link writes, which is what the rake task's "run
  # link_occurrences first" note guards. Registry-entity links (the stronger
  # grouping key) ride SyncNewsRegistryLinksJob instead, because they spend
  # model calls and the builder happily reads whatever edges exist.
  #
  # Errors are left to raise so polling telemetry records the failure.
  def perform
    HazardOccurrenceLinkService.sync_recent
    SituationBuilder.call
    # Curation (the per-situation model call) is cached on a membership
    # fingerprint; warming it now means selecting a situation never waits on
    # a live model call. Enqueued rather than inlined so a slow or failing
    # warm never reads as a failed build in polling telemetry.
    WarmSituationLayersJob.perform_later
  end
end
