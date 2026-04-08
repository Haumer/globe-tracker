require "application_system_test_case"

class TimelinePlaybackProbeTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  test "timeline auto-enables ephemeral layers and renders time-scoped data" do
    visit root_path

    if page.has_selector?("#onboarding-overlay", visible: true, wait: 5)
      find("#onboarding-dismiss").click
    end

    page.execute_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
        const originalFetch = window.fetch.bind(window)

        ;[
          ["flightsVisible", "flightsToggleTarget"],
          ["shipsVisible", "shipsToggleTarget"],
          ["situationsVisible", "situationsToggleTarget"],
          ["newsVisible", "newsToggleTarget"],
          ["verifiedStrikesVisible", "verifiedStrikesToggleTarget"],
          ["heatSignaturesVisible", "heatSignaturesToggleTarget"],
          ["earthquakesVisible", "earthquakesToggleTarget"],
          ["naturalEventsVisible", "naturalEventsToggleTarget"],
          ["gpsJammingVisible", "gpsJammingToggleTarget"],
          ["outagesVisible", "outagesToggleTarget"],
          ["financialVisible", "financialToggleTarget"],
          ["trafficVisible", "trafficToggleTarget"],
        ].forEach(([visibleProp, targetProp]) => {
          controller[visibleProp] = false
          if (controller[targetProp]) controller[targetProp].checked = false
        })

        controller.trafficArcsVisible = true
        if (controller.hasTrafficArcsToggleTarget) controller.trafficArcsToggleTarget.checked = true
        controller._timelinePlaybackBounds = { lamin: 20, lamax: 40, lomin: 40, lomax: 60 }

        window.fetch = (input, init) => {
          const url = typeof input === "string" ? input : input.url

          if (url === "/api/playback/range") {
            return Promise.resolve(new Response(JSON.stringify({
              oldest: "2026-04-06T00:00:00Z",
              newest: "2026-04-08T00:00:00Z",
              layers: {},
            }), { status: 200, headers: { "Content-Type": "application/json" } }))
          }

          if (url.startsWith("/api/playback?")) {
            const params = new URL(url, window.location.origin).searchParams
            return Promise.resolve(new Response(JSON.stringify({
              from: params.get("from"),
              to: params.get("to"),
              entity_type: params.get("type") || "all",
              frame_count: 0,
              frames: {},
            }), { status: 200, headers: { "Content-Type": "application/json" } }))
          }

          if (url.startsWith("/api/playback/events?")) {
            const parsed = new URL(url, window.location.origin)
            const types = (parsed.searchParams.get("types") || "").split(",")
            const events = []

            if (types.includes("news")) {
              events.push({
                id: "timeline-news-1",
                type: "news",
                lat: 26.5,
                lng: 56.4,
                title: "Playback news probe",
                category: "conflict",
                source: "probe",
                url: "https://example.com/news",
                time: "2026-04-06T23:00:00Z",
              })
            }

            if (types.includes("fire")) {
              events.push({
                id: "timeline-fire-1",
                type: "fire",
                external_id: "timeline-fire-1",
                lat: 26.55,
                lng: 56.45,
                brightness: 350,
                confidence: "n",
                satellite: "VIIRS",
                instrument: "VIIRS",
                frp: 18,
                daynight: "N",
                time: "2026-04-06T22:00:00Z",
              })
            }

            if (types.includes("earthquake")) {
              events.push({
                id: "timeline-eq-1",
                type: "earthquake",
                lat: 27.0,
                lng: 56.8,
                title: "Playback quake probe",
                mag: 4.6,
                magType: "Mw",
                depth: 12,
                time: "2026-04-06T21:00:00Z",
              })
            }

            return Promise.resolve(new Response(JSON.stringify(events), {
              status: 200,
              headers: { "Content-Type": "application/json" }
            }))
          }

          if (url.startsWith("/api/playback/conflicts?")) {
            return Promise.resolve(new Response(JSON.stringify({
              zones: [{
                cell_key: "26.0,56.0",
                lat: 27.0,
                lng: 57.0,
                pulse_score: 90,
                escalation_trend: "active",
                count_24h: 12,
                source_count: 6,
                situation_name: "Strait of Hormuz",
                theater: "Middle East / Iran War",
                top_headlines: ["Playback theater probe"],
              }],
              strike_arcs: [],
              hex_cells: [],
            }), { status: 200, headers: { "Content-Type": "application/json" } }))
          }

          if (url.startsWith("/api/commodities?")) {
            return Promise.resolve(new Response(JSON.stringify({
              prices: [{
                symbol: "OIL_WTI",
                category: "commodity",
                price: 74.2,
                change_pct: -3.4,
                lat: 29.0,
                lng: 48.0,
              }],
              benchmarks: [],
            }), { status: 200, headers: { "Content-Type": "application/json" } }))
          }

          if (url.startsWith("/api/internet_traffic?")) {
            return Promise.resolve(new Response(JSON.stringify({
              traffic: [{
                code: "IR",
                name: "Iran",
                traffic: 82,
                attack_origin: 0,
                attack_target: 2.4,
              }],
              attack_pairs: [{
                origin: "IR",
                target: "AE",
                origin_name: "Iran",
                target_name: "United Arab Emirates",
                pct: 5.2,
              }],
              recorded_at: "2026-04-07T20:00:00Z",
              playback: true,
            }), {
              status: 200,
              headers: {
                "Content-Type": "application/json",
                "X-Source-Configured": "1",
                "X-Source-Status": "ready",
              }
            }))
          }

          return originalFetch(input, init)
        }

        controller.timelineOpen().then(() => {
          window.__timelineProbeDone = true
        })
      })()
    JS

    assert_selector "#timeline-bar", visible: true, wait: 5

    sleep 1.0

    assert_equal true, page.evaluate_script("window.__timelineProbeDone === true")
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
        return !!(
          controller.flightsVisible &&
          controller.shipsVisible &&
          controller.situationsVisible &&
          controller.newsVisible &&
          controller.verifiedStrikesVisible &&
          controller.heatSignaturesVisible &&
          controller.financialVisible &&
          controller.trafficVisible
        )
      })()
    JS

    playback_state = page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
        return {
          conflictPulse: controller._conflictPulseData.length,
          attackArcs: controller._attackArcData.length,
          commodities: controller._commodityData.length,
        }
      })()
    JS
    assert_equal true, playback_state.values.all? { |value| value.to_i > 0 }, playback_state.inspect

    page.execute_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
        controller.timelineClose()
      })()
    JS

    assert_no_selector "#timeline-bar", visible: true, wait: 5
    assert_equal false, page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
        return !!(
          controller.flightsVisible ||
          controller.shipsVisible ||
          controller.situationsVisible ||
          controller.newsVisible ||
          controller.verifiedStrikesVisible ||
          controller.heatSignaturesVisible ||
          controller.financialVisible ||
          controller.trafficVisible
        )
      })()
    JS
  end
end
