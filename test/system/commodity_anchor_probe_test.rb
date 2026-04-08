require "application_system_test_case"

class CommodityAnchorProbeTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  test "commodity detail uses anchored popup instead of legacy detail panel" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    page.execute_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")

        controller._commodityData = [{
          symbol: "OIL_WTI",
          name: "Crude Oil (WTI)",
          category: "commodity",
          region: "United States",
          price: 74.8,
          change_pct: -2.3,
          unit: "USD/barrel",
          lat: 24.71,
          lng: 46.67,
          recorded_at: new Date().toISOString()
        }]

        controller.showCommodityDetail(controller._commodityData[0])
      })()
    JS

    assert_selector "#anchor-panel", visible: true, wait: 5
    assert_equal "commodity", page.evaluate_script("document.querySelector('#anchor-panel').dataset.kind")

    assert_equal "none", page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector('#detail-panel')
        return panel ? window.getComputedStyle(panel).display : "missing"
      })()
    JS
  end
end
