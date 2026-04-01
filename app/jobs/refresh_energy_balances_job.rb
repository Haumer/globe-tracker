class RefreshEnergyBalancesJob < ApplicationJob
  queue_as :background
  tracks_polling source: "energy-balances", poll_type: "energy_balances"

  def perform
    EnergyBalanceRefreshService.refresh_if_stale
  end
end
