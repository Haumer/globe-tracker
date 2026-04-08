require "application_system_test_case"

class ChokepointContextProbeTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  test "chokepoint detail opens anchor and right pane" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    page.execute_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")

        controller._chokepointData = [{
          id: "probe-chokepoint-1",
          name: "Probe Strait",
          status: "elevated",
          region: "Middle East",
          lat: 26.56,
          lng: 56.27,
          ships_nearby: { total: 11, tankers: 4 },
          commodity_signals: [{
            symbol: "OIL_WTI",
            name: "Crude Oil (WTI)",
            price: 74.8,
            change_pct: -2.3
          }],
          supply_chain_lens: {
            dependency_map: {
              summary: "Probe dependency rows.",
              rows: [{
                country_name: "India",
                country_code_alpha3: "IND",
                exposure_score: 0.68,
                import_share_gdp_pct: 1.4,
                estimated: true,
                bucket: "high",
                bucket_label: "High",
                bucket_color: "#ff9800"
              }]
            },
            reserve_runway: {
              summary: "Probe reserve runway.",
              cards: [{
                country_name: "India",
                country_code_alpha3: "IND",
                runway_days: 41,
                supplier_share_pct: 21.0,
                coverage_mode: "estimated",
                status: "high"
              }]
            },
            downstream_pathway: {
              summary: "Probe downstream pathway.",
              stages: [{
                phase: "Day 1",
                title: "Transit disruption",
                description: "Route stress reaches downstream refiners."
              }]
            }
          }
        }]

        controller.showChokepointDetail("probe-chokepoint-1")
      })()
    JS

    assert_selector "#anchor-panel", visible: true, wait: 5
    assert_equal "chokepoint", page.evaluate_script("document.querySelector('#anchor-panel').dataset.kind")

    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector('#right-panel')
        return !!panel && window.getComputedStyle(panel).display !== "none"
      })()
    JS

    assert_text "DEPENDENCY MAP"
  end
end
