require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "sidebar constants are defined" do
    assert_kind_of Array, ApplicationHelper::PRIMARY_SIDEBAR_LAYER_DEFS
    assert_kind_of Array, ApplicationHelper::ADVANCED_SIDEBAR_LIBRARY_DEFS
    assert ApplicationHelper::PRIMARY_SIDEBAR_LAYER_DEFS.frozen?
    assert ApplicationHelper::ADVANCED_SIDEBAR_LIBRARY_DEFS.frozen?
  end

  test "sidebar_primary_layers returns frozen array" do
    layers = sidebar_primary_layers
    assert_kind_of Array, layers
    assert layers.any? { |l| l[:key] == "situations" }
    assert layers.any? { |l| l[:key] == "news" }
  end

  test "sidebar_advanced_library_layers returns frozen array" do
    layers = sidebar_advanced_library_layers
    assert_kind_of Array, layers
    assert layers.any? { |l| l[:key] == "flights" }
    assert layers.any? { |l| l[:key] == "cameras" }
  end

  test "sidebar_advanced_library_layers_by_key indexes by key" do
    by_key = sidebar_advanced_library_layers_by_key
    assert_kind_of Hash, by_key
    assert_equal "Flights", by_key["flights"][:label]
    assert_equal "Webcams", by_key["cameras"][:label]
  end

  test "enabled_sidebar_library_layers with no user returns empty" do
    result = enabled_sidebar_library_layers(nil)
    assert_equal [], result
  end

  test "enabled_sidebar_library_layers extracts enabled layers from prefs" do
    user = OpenStruct.new(preferences: {
      "layers" => { "flights" => true, "ships" => true, "unknown_layer" => true },
      "enabled_layers" => ["cameras"],
    })

    result = enabled_sidebar_library_layers(user)
    assert_includes result, "flights"
    assert_includes result, "ships"
    assert_includes result, "cameras"
    assert_not_includes result, "unknown_layer"
  end

  test "enabled_sidebar_library_layers expands strikes to verified and heat" do
    user = OpenStruct.new(preferences: {
      "layers" => { "strikes" => true },
    })

    result = enabled_sidebar_library_layers(user)
    assert_includes result, "verifiedStrikes"
    assert_includes result, "heatSignatures"
  end

  test "enabled_sidebar_library_layers includes satellites when satCategories present" do
    user = OpenStruct.new(preferences: {
      "layers" => { "satCategories" => { "gps" => true } },
    })

    result = enabled_sidebar_library_layers(user)
    assert_includes result, "satellites"
  end
end
