require "test_helper"

class UiRegistryContractTest < ActiveSupport::TestCase
  REGISTRY_PATH = Rails.root.join("app/javascript/globe/controller/ui/registry.js")

  test "advanced sidebar layer keys stay aligned with the ui registry contract" do
    source = File.read(REGISTRY_PATH)

    registry_keys = source.scan(/\{\s*key: "([^"]+)"/).flatten
    advanced_keys_match = source.match(/export const ADVANCED_LIBRARY_KEYS = \[(.*?)\]/m)

    assert advanced_keys_match, "Expected ui registry to export ADVANCED_LIBRARY_KEYS"

    advanced_keys = advanced_keys_match[1].scan(/"([^"]+)"/).flatten
    helper_keys = ApplicationHelper::ADVANCED_SIDEBAR_LIBRARY_DEFS.map { |layer| layer[:key] }

    assert_equal helper_keys, advanced_keys,
                 "Advanced layer keys in ApplicationHelper and ui/registry.js must stay in sync"

    missing_registry_keys = helper_keys.reject { |key| key == "satellites" || registry_keys.include?(key) }

    assert missing_registry_keys.empty?,
           "Advanced layer keys missing from LAYER_REGISTRY: #{missing_registry_keys.join(', ')}"
  end
end
