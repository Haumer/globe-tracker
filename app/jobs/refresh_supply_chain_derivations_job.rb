class RefreshSupplyChainDerivationsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "derived-supply-chain", poll_type: "derived_layer"

  def perform
    SupplyChainNormalizationService.refresh_if_stale
  end
end
