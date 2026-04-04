class GenerateTheaterBriefJob < ApplicationJob
  queue_as :background

  def perform(scope_key, zone_payload)
    snapshot = TheaterBriefService.refresh(scope_key:, zone_payload:, force: true)
    brief = snapshot.payload["brief"] || {}
    { records_fetched: Array(brief["key_developments"]).size, records_stored: 1 }
  end
end
