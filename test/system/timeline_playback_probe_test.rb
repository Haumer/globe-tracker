require "application_system_test_case"
require "timeout"

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
    playback_visibility = page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector('[data-controller="globe"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "globe")
        return {
          flightsVisible: !!controller.flightsVisible,
          shipsVisible: !!controller.shipsVisible,
          situationsVisible: !!controller.situationsVisible,
          newsVisible: !!controller.newsVisible,
          verifiedStrikesVisible: !!controller.verifiedStrikesVisible,
          heatSignaturesVisible: !!controller.heatSignaturesVisible,
          financialVisible: !!controller.financialVisible,
          trafficVisible: !!controller.trafficVisible,
        }
      })()
    JS
    assert_equal false, playback_visibility["flightsVisible"], playback_visibility.inspect
    assert_equal false, playback_visibility["shipsVisible"], playback_visibility.inspect
    assert_equal true, playback_visibility["situationsVisible"], playback_visibility.inspect
    assert_equal true, playback_visibility["newsVisible"], playback_visibility.inspect
    assert_equal true, playback_visibility["verifiedStrikesVisible"], playback_visibility.inspect
    assert_equal true, playback_visibility["heatSignaturesVisible"], playback_visibility.inspect
    assert_equal true, playback_visibility["financialVisible"], playback_visibility.inspect
    assert_equal true, playback_visibility["trafficVisible"], playback_visibility.inspect

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

  test "timeline playback appends news and updates theater state as the cursor advances" do
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

        controller.newsVisible = true
        controller.situationsVisible = true
        if (controller.newsToggleTarget) controller.newsToggleTarget.checked = true
        if (controller.situationsToggleTarget) controller.situationsToggleTarget.checked = true
        controller._timelinePlaybackBounds = { lamin: 20, lamax: 40, lomin: 40, lomax: 60 }

        const newsCandidates = [
          {
            id: "timeline-news-early",
            type: "news",
            lat: 26.5,
            lng: 56.4,
            title: "Early playback news",
            category: "conflict",
            source: "probe",
            url: "https://example.com/news-1",
            time: "2026-04-06T20:15:00Z",
          },
          {
            id: "timeline-news-late",
            type: "news",
            lat: 26.8,
            lng: 56.6,
            title: "Late playback news",
            category: "conflict",
            source: "probe",
            url: "https://example.com/news-2",
            time: "2026-04-06T22:15:00Z",
          },
        ]

        window.__timelinePlaybackProbe = { eventFetches: 0, conflictFetches: 0 }

        window.fetch = (input, init) => {
          const url = typeof input === "string" ? input : input.url

          if (url === "/api/playback/range") {
            return Promise.resolve(new Response(JSON.stringify({
              oldest: "2026-04-06T20:00:00Z",
              newest: "2026-04-06T23:00:00Z",
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
            window.__timelinePlaybackProbe.eventFetches += 1
            const parsed = new URL(url, window.location.origin)
            const from = new Date(parsed.searchParams.get("from")).getTime()
            const to = new Date(parsed.searchParams.get("to")).getTime()
            const types = (parsed.searchParams.get("types") || "").split(",")
            const events = []

            if (types.includes("news")) {
              newsCandidates.forEach((event) => {
                const eventMs = new Date(event.time).getTime()
                if (eventMs >= from && eventMs <= to) events.push(event)
              })
            }

            return Promise.resolve(new Response(JSON.stringify(events), {
              status: 200,
              headers: { "Content-Type": "application/json" }
            }))
          }

          if (url.startsWith("/api/playback/conflicts?")) {
            window.__timelinePlaybackProbe.conflictFetches += 1
            const parsed = new URL(url, window.location.origin)
            const at = new Date(parsed.searchParams.get("at"))
            const hour = at.getUTCHours()
            const isLate = hour >= 22

            return Promise.resolve(new Response(JSON.stringify({
              zones: [{
                cell_key: "26.0,56.0",
                lat: 27.0,
                lng: 57.0,
                pulse_score: isLate ? 92 : 41,
                escalation_trend: isLate ? "surging" : "active",
                count_24h: isLate ? 19 : 7,
                source_count: isLate ? 9 : 4,
                situation_name: "Strait of Hormuz",
                theater: "Middle East / Iran War",
                top_headlines: [isLate ? "Late playback theater" : "Early playback theater"],
              }],
              strike_arcs: [],
              hex_cells: [],
            }), { status: 200, headers: { "Content-Type": "application/json" } }))
          }

          return originalFetch(input, init)
        }

        controller.timelineOpen().then(() => {
          controller._timelineCursor = new Date("2026-04-06T22:30:00Z")
          controller._updateTimelineCursorDisplay()
          controller._renderNearestFrame()
          return controller._timelineRefreshPlaybackState()
        }).then(() => {
          window.__timelinePlaybackProbeResult = {
            eventFetches: window.__timelinePlaybackProbe.eventFetches,
            conflictFetches: window.__timelinePlaybackProbe.conflictFetches,
            newsCount: controller._newsData.length,
            latestNewsTitle: controller._newsData[controller._newsData.length - 1]?.title || null,
            pulseScore: controller._conflictPulseData[0]?.pulse_score || null,
            pulseHeadline: controller._conflictPulseData[0]?.top_headlines?.[0] || null,
          }
        }).catch((error) => {
          window.__timelinePlaybackProbeResult = {
            error: String(error),
            stack: error && error.stack ? error.stack : null,
          }
        })
      })()
    JS

    assert_selector "#timeline-bar", visible: true, wait: 5

    Timeout.timeout(5) do
      loop do
        break if page.evaluate_script("!!window.__timelinePlaybackProbeResult")
        sleep 0.1
      end
    end

    playback_state = JSON.parse(page.evaluate_script("JSON.stringify(window.__timelinePlaybackProbeResult)"))
    assert_nil playback_state["error"], playback_state.inspect
    assert_operator playback_state["eventFetches"], :>=, 2, playback_state.inspect
    assert_operator playback_state["conflictFetches"], :>=, 2, playback_state.inspect
    assert_equal 2, playback_state["newsCount"], playback_state.inspect
    assert_equal "Late playback news", playback_state["latestNewsTitle"], playback_state.inspect
    assert_equal 92, playback_state["pulseScore"], playback_state.inspect
    assert_equal "Late playback theater", playback_state["pulseHeadline"], playback_state.inspect
  end
end
