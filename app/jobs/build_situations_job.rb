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
  end
end
