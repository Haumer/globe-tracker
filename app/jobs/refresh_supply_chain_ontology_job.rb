class RefreshSupplyChainOntologyJob < ApplicationJob
  queue_as :background
  tracks_polling source: "derived-supply-chain-ontology", poll_type: "ontology"

  def perform
    SupplyChainOntologySyncService.sync_recent
  end
end
