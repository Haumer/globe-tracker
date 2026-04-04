require "application_system_test_case"

class PortsToggleTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  test "ports quick toggle activates from the sidebar" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    find('.sb-section[data-section="infrastructure"] .sb-section-head', wait: 20).click
    assert_selector '[data-globe-target="qlPorts"]', wait: 20

    port_row = find('[data-globe-target="qlPorts"]')
    port_row.click

    assert_equal true, page.evaluate_script('document.querySelector(\'[data-globe-target="portsToggle"]\').checked')
    assert_equal true, page.evaluate_script('document.querySelector(\'[data-globe-target="qlPorts"]\').classList.contains("active")')
  end
end
