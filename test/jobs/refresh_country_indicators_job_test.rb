require "test_helper"

class RefreshCountryIndicatorsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshCountryIndicatorsJob.new.queue_name
  end

  test "tracks polling with source world-bank-wdi and poll_type country_indicators" do
    assert_equal "world-bank-wdi", RefreshCountryIndicatorsJob.polling_source_resolver
    assert_equal "country_indicators", RefreshCountryIndicatorsJob.polling_type_resolver
  end

  test "calls CountryIndicatorRefreshService.refresh_if_stale" do
    called = false
    CountryIndicatorRefreshService.stub(:refresh_if_stale, -> { called = true; 5 }) do
      RefreshCountryIndicatorsJob.perform_now
    end
    assert called
  end
end
