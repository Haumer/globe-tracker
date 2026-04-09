require "test_helper"

class RefreshWeatherAlertsJobTest < ActiveSupport::TestCase
  test "is assigned to the default queue" do
    assert_equal "default", RefreshWeatherAlertsJob.new.queue_name
  end

  test "tracks polling with source weather-alerts and poll_type weather_alerts" do
    assert_equal "weather-alerts", RefreshWeatherAlertsJob.polling_source_resolver
    assert_equal "weather_alerts", RefreshWeatherAlertsJob.polling_type_resolver
  end

  test "calls WeatherAlertRefreshService.refresh_if_stale" do
    called = false
    WeatherAlertRefreshService.stub(:refresh_if_stale, -> { called = true; 5 }) do
      RefreshWeatherAlertsJob.perform_now
    end
    assert called
  end
end
