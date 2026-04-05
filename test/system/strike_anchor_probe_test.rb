require "application_system_test_case"

class StrikeAnchorProbeTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  test "directly opened strike anchor remains visible" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    page.execute_script(<<~JS)
      const element = document.querySelector('[data-controller="globe"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
      window.__strikeAnchorProbe = controller
      controller._showCompactEntityDetail("strike", {
        id: "probe-strike-1",
        lat: 32.08,
        lng: 34.78,
        strikeConfidence: "high",
        title: "Probe strike",
        satellite: "VIIRS",
        frp: 25,
        clusterSize: 1,
      })
    JS

    assert_selector "#anchor-panel", visible: true, wait: 5
    assert_equal "strike", page.evaluate_script("document.querySelector('#anchor-panel').dataset.kind")

    sleep 0.3

    assert_equal "", page.evaluate_script("document.querySelector('#anchor-panel').style.display")
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector('#anchor-panel')
        const rect = panel.getBoundingClientRect()
        return window.getComputedStyle(panel).display !== "none" && rect.width > 0 && rect.height > 0
      })()
    JS
  end

  test "strike anchor survives delayed empty click after open" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    page.execute_script(<<~JS)
      const element = document.querySelector('[data-controller="globe"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")

      const strike = {
        id: "probe-strike-2",
        lat: 32.08,
        lng: 34.78,
        strikeConfidence: "high",
        title: "Probe strike delayed",
        satellite: "VIIRS",
        frp: 25,
        clusterSize: 1,
      }

      controller._showCompactEntityDetail("strike", strike, { id: strike.id })

      setTimeout(() => {
        controller.closeDetail()
      }, 250)
    JS

    assert_selector "#anchor-panel", visible: true, wait: 5

    sleep 0.5

    assert_equal "", page.evaluate_script("document.querySelector('#anchor-panel').style.display")
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector('#anchor-panel')
        const rect = panel.getBoundingClientRect()
        return window.getComputedStyle(panel).display !== "none" && rect.width > 0 && rect.height > 0
      })()
    JS
  end

  test "strike anchor closes once offscreen grace has elapsed" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    page.execute_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")

        const strike = {
          id: "probe-strike-3",
          lat: 32.08,
          lng: 34.78,
          strikeConfidence: "high",
          title: "Probe strike offscreen",
          satellite: "VIIRS",
          frp: 25,
          clusterSize: 1,
        }

        controller._showCompactEntityDetail("strike", strike, { id: strike.id })
      })()
    JS

    assert_selector "#anchor-panel", visible: true, wait: 5

    page.execute_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
        const original = controller._anchoredDetailScreenPoint.bind(controller)
        controller._anchoredDetailState._offscreenSince = controller._anchoredDetailNow() - 500
        controller._anchoredDetailScreenPoint = () => null
        controller._refreshAnchoredDetailPosition(true)
        controller._anchoredDetailScreenPoint = original
      })()
    JS

    assert_no_selector "#anchor-panel", visible: true, wait: 2

    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
        return !controller._anchoredDetailState
      })()
    JS

    assert_equal false, page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector('#anchor-panel')
        return window.getComputedStyle(panel).display !== "none"
      })()
    JS
  end
end
