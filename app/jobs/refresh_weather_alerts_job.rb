class RefreshWeatherAlertsJob < ApplicationJob
  queue_as :default

  def perform
    WeatherAlertRefreshService.refresh_if_stale
  end
end
