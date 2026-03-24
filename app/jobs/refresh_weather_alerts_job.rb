class RefreshWeatherAlertsJob < ApplicationJob
  queue_as :default
  tracks_polling source: "weather-alerts", poll_type: "weather_alerts"

  def perform
    WeatherAlertRefreshService.refresh_if_stale
  end
end
