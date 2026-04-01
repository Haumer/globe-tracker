class RefreshCountryIndicatorsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "world-bank-wdi", poll_type: "country_indicators"

  def perform
    CountryIndicatorRefreshService.refresh_if_stale
  end
end
