require "application_system_test_case"

class PipelineContextProbeTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  test "pipeline detail opens anchor and right pane" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    page.execute_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")

        controller._pipelineData = [{
          id: "probe-pipeline-1",
          name: "Probe Pipeline",
          type: "oil",
          status: "operational",
          country: "Saudi Arabia",
          length_km: 1200,
          coordinates: [[24.4, 46.1], [25.1, 49.2]],
          market_context: {
            summary: "Probe market context",
            benchmarks: [{
              symbol: "OIL_WTI",
              category: "commodity",
              name: "Crude Oil (WTI)",
              price: 78.5,
              change_pct: 2.1,
              unit: "USD/barrel",
              recorded_at: new Date().toISOString()
            }],
            benchmark_series: {
              OIL_WTI: [
                { price: 75.2 },
                { price: 76.0 },
                { price: 77.4 },
                { price: 78.5 }
              ]
            },
            highlights: ["WTI reacting higher on route risk."],
            supply_chain_lens: {
              dependency_map: {
                summary: "Probe dependency rows.",
                rows: [{
                  country_name: "India",
                  country_code_alpha3: "IND",
                  exposure_score: 0.61,
                  import_share_gdp_pct: 1.2,
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
                  supplier_share_pct: 18.0,
                  coverage_mode: "estimated",
                  status: "high"
                }]
              },
              downstream_pathway: {
                summary: "Probe downstream pathway.",
                stages: [{
                  phase: "Day 1",
                  title: "Crude flow shock",
                  description: "Initial route shock reaches refiners."
                }]
              }
            }
          }
        }]

        controller.showPipelineDetail("probe-pipeline-1")
      })()
    JS

    assert_selector "#anchor-panel", visible: true, wait: 5
    assert_equal "pipeline", page.evaluate_script("document.querySelector('#anchor-panel').dataset.kind")

    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector('#right-panel')
        return !!panel && window.getComputedStyle(panel).display !== "none"
      })()
    JS

    assert_text "DEPENDENCY MAP"
  end
end
