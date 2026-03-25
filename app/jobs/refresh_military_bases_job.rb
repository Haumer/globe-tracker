class RefreshMilitaryBasesJob < ApplicationJob
  queue_as :background
  tracks_polling source: "military-bases", poll_type: "military_bases"

  def perform
    MilitaryBaseRefreshService.refresh_if_stale
  end
end
