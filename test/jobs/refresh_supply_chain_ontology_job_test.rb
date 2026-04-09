require "test_helper"

class RefreshSupplyChainOntologyJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshSupplyChainOntologyJob.new.queue_name
  end

  test "tracks polling with source derived-supply-chain-ontology and poll_type ontology" do
    assert_equal "derived-supply-chain-ontology", RefreshSupplyChainOntologyJob.polling_source_resolver
    assert_equal "ontology", RefreshSupplyChainOntologyJob.polling_type_resolver
  end

  test "calls SupplyChainOntologySyncService.sync_recent" do
    called = false
    SupplyChainOntologySyncService.stub(:sync_recent, -> { called = true; 3 }) do
      RefreshSupplyChainOntologyJob.perform_now
    end
    assert called
  end
end
