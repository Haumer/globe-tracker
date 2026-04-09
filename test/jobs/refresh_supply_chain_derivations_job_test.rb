require "test_helper"

class RefreshSupplyChainDerivationsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshSupplyChainDerivationsJob.new.queue_name
  end

  test "tracks polling with source derived-supply-chain and poll_type derived_layer" do
    assert_equal "derived-supply-chain", RefreshSupplyChainDerivationsJob.polling_source_resolver
    assert_equal "derived_layer", RefreshSupplyChainDerivationsJob.polling_type_resolver
  end

  test "calls SupplyChainNormalizationService.refresh_if_stale" do
    called = false
    SupplyChainNormalizationService.stub(:refresh_if_stale, -> { called = true; 10 }) do
      RefreshSupplyChainDerivationsJob.perform_now
    end
    assert called
  end
end
