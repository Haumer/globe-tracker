require "test_helper"

class LayerAvailabilityTest < ActiveSupport::TestCase
  teardown do
    LayerAvailability.disabled_layers = nil
  end

  test "disabled? returns true for disabled layers" do
    assert LayerAvailability.disabled?("trains")
    assert LayerAvailability.disabled?("railways")
    assert LayerAvailability.disabled?("shipping_lanes")
  end

  test "disabled? returns false for enabled layers" do
    refute LayerAvailability.disabled?("flights")
    refute LayerAvailability.disabled?("earthquakes")
  end

  test "enabled? returns true for non-disabled layers" do
    assert LayerAvailability.enabled?("flights")
    assert LayerAvailability.enabled?("earthquakes")
  end

  test "enabled? returns false for disabled layers" do
    refute LayerAvailability.enabled?("trains")
    refute LayerAvailability.enabled?("railways")
  end

  test "disabled? handles symbol keys" do
    assert LayerAvailability.disabled?(:trains)
    refute LayerAvailability.disabled?(:flights)
  end

  test "disabled? handles camelCase keys via underscore normalization" do
    assert LayerAvailability.disabled?(:shippingLanes)
    assert LayerAvailability.disabled?("ShippingLanes")
  end

  test "disabled_layers can be overridden" do
    LayerAvailability.disabled_layers = %w[custom_layer]

    assert LayerAvailability.disabled?("custom_layer")
    refute LayerAvailability.disabled?("trains")
  end

  test "DISABLED_LAYERS contains expected defaults" do
    assert_includes LayerAvailability::DISABLED_LAYERS, "trains"
    assert_includes LayerAvailability::DISABLED_LAYERS, "railways"
    assert_includes LayerAvailability::DISABLED_LAYERS, "shipping_lanes"
  end
end
