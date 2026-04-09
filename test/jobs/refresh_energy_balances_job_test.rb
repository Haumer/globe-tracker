require "test_helper"

class RefreshEnergyBalancesJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshEnergyBalancesJob.new.queue_name
  end

  test "tracks polling with source energy-balances and poll_type energy_balances" do
    assert_equal "energy-balances", RefreshEnergyBalancesJob.polling_source_resolver
    assert_equal "energy_balances", RefreshEnergyBalancesJob.polling_type_resolver
  end

  test "calls EnergyBalanceRefreshService.refresh_if_stale" do
    called = false
    EnergyBalanceRefreshService.stub(:refresh_if_stale, -> { called = true; 3 }) do
      RefreshEnergyBalancesJob.perform_now
    end
    assert called
  end
end
