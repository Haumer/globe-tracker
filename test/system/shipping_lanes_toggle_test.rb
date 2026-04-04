require "application_system_test_case"

class ShippingLanesToggleTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  test "shipping, railway, and train layers stay disabled in the sidebar" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    find('.sb-section[data-section="tracking"] .sb-section-head', wait: 20).click
    assert_disabled_layer("qlTrains", "trainsToggle")

    find('.sb-section[data-section="infrastructure"] .sb-section-head', wait: 20).click
    assert_disabled_layer("qlShippingLanes", "shippingLanesToggle")
    assert_disabled_layer("qlRailways", "railwaysToggle")
  end

  private

  def assert_disabled_layer(row_target, toggle_target)
    assert_selector %[ [data-globe-target="#{row_target}"].sb-disabled ], wait: 20

    row = find(%([data-globe-target="#{row_target}"]))
    row.click

    assert_equal false, page.evaluate_script(%(document.querySelector('[data-globe-target="#{toggle_target}"]').checked))
    assert_equal true, page.evaluate_script(%(document.querySelector('[data-globe-target="#{row_target}"]').classList.contains("sb-disabled")))
    assert_equal "true", page.evaluate_script(%(document.querySelector('[data-globe-target="#{row_target}"]').getAttribute("aria-disabled")))
  end
end
