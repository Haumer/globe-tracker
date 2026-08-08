class RefreshFireClustersJob < ApplicationJob
  queue_as :default
  tracks_polling source: "derived-fire-clusters", poll_type: "derived_layer"

  def perform
    count = FireClusterService.refresh
    { records_fetched: count, records_stored: count }
  end
end
