import { getDataSource } from "globe/utils"
import {
  ambientColor,
  ambientHaloPoint,
  ambientOutlineWidth,
  ambientPointSize,
  beginAmbientLayer,
  haloWeightCutoff,
  clearAmbientLayer,
  commitAmbientLayer,
  registerAmbient,
} from "globe/controller/ambient_pulse"
import { newsCategoryColor } from "globe/controller/news_palette"

// geo_precision values that mean we resolved an actual place. Everything else is
// a country centroid or a give-up, and gets drawn as a wash rather than a point.
const LOCATED_PRECISIONS = new Set(["city", "place", "airport", "region"])

// How many headlines may be on the globe at once. Nothing declutters labels, so
// this is the whole density control.
const LABEL_BUDGET = 14

export function applyNewsRenderingMethods(GlobeController) {
  GlobeController.prototype.getNewsDataSource = function() { return getDataSource(this.viewer, this._ds, "news") }

  GlobeController.prototype._pointInRegion = function(lat, lng, regionKey) {
    if (regionKey === "all") return true
    const r = this.constructor.NEWS_REGIONS[regionKey]
    if (!r) return true
    return lat >= r.latMin && lat <= r.latMax && lng >= r.lngMin && lng <= r.lngMax
  }

  GlobeController.prototype.toggleNews = function() {
    this.newsVisible = this.hasNewsToggleTarget && this.newsToggleTarget.checked
    if (this._newsInterval) {
      clearInterval(this._newsInterval)
      this._newsInterval = null
    }

    if (this.newsVisible) {
      if (this._timelineActive) {
        this._timelineOnLayerToggle?.()
      } else {
        this.fetchNews()
        this._newsInterval = setInterval(() => this.fetchNews(), 900000)
      }
      if (this.hasNewsArcControlsTarget) this.newsArcControlsTarget.style.display = ""
    } else {
      this._clearNewsEntities()
      this._newsData = []
      this._updateStats?.()
      if (this.hasNewsArcControlsTarget) this.newsArcControlsTarget.style.display = "none"
    }
    this._syncQuickBar()
    if (this._syncRightPanels) this._syncRightPanels()
    if (this.newsVisible && this._newsData?.length > 0) this._showRightPanel("news")
    this._savePrefs()
  }

  GlobeController.prototype.toggleNewsArcs = function() {
    this.newsArcsVisible = this.hasNewsArcsToggleTarget && this.newsArcsToggleTarget.checked
    if (!this.newsArcsVisible) {
      this.newsBlobsVisible = false
      if (this.hasNewsBlobsToggleTarget) this.newsBlobsToggleTarget.checked = false
      this._clearNewsArcEntities()
    }
  }

  GlobeController.prototype.toggleNewsBlobs = function() {
    this.newsBlobsVisible = this.hasNewsBlobsToggleTarget && this.newsBlobsToggleTarget.checked
    if (this.newsBlobsVisible && !this.newsArcsVisible) {
      this.newsBlobsVisible = false
      if (this.hasNewsBlobsToggleTarget) this.newsBlobsToggleTarget.checked = false
      return
    }
    if (!this.newsBlobsVisible) {
      this._stopNewsArcBlobAnim()
      this._removeNewsBlobEntities()
    }
  }

  GlobeController.prototype.applyNewsArcFilter = function() {}

  GlobeController.prototype.toggleNewsClustering = function() {
    this.fetchNews()
  }

  GlobeController.prototype.fetchNews = async function() {
    if (this._timelineActive) return
    this._toast("Loading news...")
    try {
      const url = "/api/news?clustered=true"
      const resp = await fetch(url)
      if (!resp.ok) {
        console.error("News API error:", resp.status)
        this._toastHide()
        return
      }
      const events = await resp.json()
      this._handleBackgroundRefresh(resp, "news", events.length > 0, () => {
        if (this.newsVisible && !this._timelineActive) this.fetchNews()
      })
      this._newsData = this.filterToRegion(events)
      this._renderNews(this._newsData)
      // Every other layer refreshes the stats bar after loading; news never did,
      // so the header read "NEWS 0" with a few hundred clusters on the globe.
      this._updateStats?.()
      this._markFresh("news")
      if (this._syncRightPanels) this._syncRightPanels()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch news:", e)
      this._toastHide()
    }
  }

  GlobeController.prototype._renderNews = function(events) {
    this._clearNewsEntities()
    const dataSource = this.getNewsDataSource()
    dataSource.show = true

    const ambient = !this._timelineActive
    if (ambient) beginAmbientLayer(this, "news")
    // Article index -> the pin that represents it. A pin stands for a whole
    // cluster, so several article indices map to the same entity. The feed can
    // only address articles by their index in _newsData, and _newsEntities is
    // ordered by cluster with halos and threat rings interleaved -- indexing one
    // with the other picked an unrelated pin.
    this._newsEntityByEventIdx = new Map()
    // Read live so _setNewsDotOpacity can dim the layer without replacing callbacks.
    const dotOpacity = () => (Number.isFinite(this._newsDotOpacity) ? this._newsDotOpacity : 1)

    // Math.round yields -0 for anything in (-0.5, 0], and "-0" is a different
    // string from "0" -- which quietly split every cell touching the equator or
    // the prime meridian into as many as four.
    const cell = value => (Math.round(value) === 0 ? 0 : Math.round(value))

    const clusters = new Map()
    events.forEach((ev, i) => {
      const key = `${cell(ev.lat)},${cell(ev.lng)}`
      if (!clusters.has(key)) clusters.set(key, [])
      clusters.get(key).push({ ...ev, _idx: i })
    })

    // Weight decides size, halo and -- because there is no declutter -- which
    // clusters are allowed a label at all. Significance leads: with tone finally
    // populated, `priority` (|tone| decayed by age) separates stories, whereas
    // cluster count mostly reports how many centroids share a degree cell.
    const weigh = (lead, count) => {
      const intensity = Math.min((lead.priority != null ? lead.priority : Math.abs(lead.tone || 0)) / 10, 1)
      const coverage = Math.min(Math.log2(count + 1) / 3, 1)
      return (intensity * 0.65) + (coverage * 0.35)
    }

    const ranked = [...clusters.values()].map((clusterEvents) => {
      clusterEvents.sort((a, b) => (b.priority || Math.abs(b.tone || 0)) - (a.priority || Math.abs(a.tone || 0)))
      return { clusterEvents, weight: weigh(clusterEvents[0], clusterEvents.length) }
    }).sort((a, b) => b.weight - a.weight)

    // Sizes are relative to the loudest story on screen, not to an absolute
    // scale. `priority` decays exponentially with age, so on a quiet night every
    // event is old, every weight is near the floor, and an absolute ramp would
    // render the entire globe at minimum size. Relative scaling keeps the map
    // readable at 3am and still says "this is the big one".
    const topWeight = ranked[0]?.weight || 1

    const haloCutoff = ambient ? haloWeightCutoff(ranked.map(r => r.weight)) : Infinity
    // Nothing in Cesium declutters labels for us and there is no EntityCluster in
    // this codebase, so the only way 250-odd headlines do not overprint each other
    // is to not draw most of them. Same idea as the ports label budget.
    const labelCutoff = ranked.length > LABEL_BUDGET ? ranked[LABEL_BUDGET - 1].weight : -Infinity

    ranked.forEach(({ clusterEvents, weight }) => {
      const lead = clusterEvents[0]
      const count = clusterEvents.length
      const color = newsCategoryColor(lead.category)
      const cesiumColor = Cesium.Color.fromCssColorString(color)

      const avgLat = clusterEvents.reduce((s, e) => s + e.lat, 0) / count
      const avgLng = clusterEvents.reduce((s, e) => s + e.lng, 0) / count

      const coverageBoost = Math.min(Math.log2(count + 1) / 3, 1)

      // Whether we know where this actually happened. Roughly half of events are
      // country centroids -- often the publisher's own country rather than the
      // story's -- and drawing those as a crisp dot on a capital city asserts a
      // precision we do not have.
      const located = LOCATED_PRECISIONS.has(lead.geo_precision)

      // One continuous ramp. The old code hardcoded [48, 36, 28] for the three
      // biggest cells, which left nothing between 20 and 28px and broke entirely
      // if the third-largest cell was a singleton. It existed because tone was
      // always zero, so cluster count was the only thing left to separate on.
      let pixelSize = 7 + (weight / topWeight) * 15
      // A vague position gets a bigger, softer mark: it covers more ground because
      // it means less.
      if (!located) pixelSize *= 1.3

      const fillAlpha = located ? 0.92 : 0.3
      const outlineAlpha = located ? 0.45 + coverageBoost * 0.3 : 0.55
      const outlineWidth = located ? 1 + Math.round(coverageBoost * 2) : 2

      const showLabel = weight >= labelCutoff
      const headline = showLabel ? this._truncateNewsLabel(lead.title || lead.name, weight >= 0.5 ? 50 : 30) : ""
      const labelText = count > 1 ? `${headline}  (+${count - 1})` : headline

      // Keyed on the cluster's rounded centroid so a story cluster keeps the same
      // phase across the 15-minute refresh instead of restarting its breath.
      const ambientKey = ambient
        ? registerAmbient(this, "news", `${avgLat.toFixed(2)},${avgLng.toFixed(2)}`, {
            lat: avgLat,
            lng: avgLng,
            weight,
          })
        : null

      if (ambientKey && weight >= haloCutoff) {
        const halo = ambientHaloPoint(this, ambientKey, cesiumColor, {
          minSize: pixelSize,
          maxSize: pixelSize + 18 + coverageBoost * 34,
          peakAlpha: 0.14 + coverageBoost * 0.24,
          opacity: dotOpacity,
        })
        if (halo) {
          const haloEntity = dataSource.entities.add({
            id: `news-halo-${lead._idx}`,
            position: Cesium.Cartesian3.fromDegrees(avgLng, avgLat, 5),
            point: { ...halo, scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5) },
          })
          this._newsEntities.push(haloEntity)
        }
      }

      const entity = dataSource.entities.add({
        id: `news-${lead._idx}`,
        position: Cesium.Cartesian3.fromDegrees(avgLng, avgLat, 10),
        point: {
          pixelSize: ambientKey ? ambientPointSize(this, ambientKey, pixelSize, 0.12) : pixelSize,
          // A located dot is solid; a country centroid is a wash you can see the
          // globe through. Same hue, so category still reads -- only the claim to
          // knowing where it happened changes.
          color: ambientKey
            ? ambientColor(this, ambientKey, cesiumColor, fillAlpha, 0.16, dotOpacity)
            : cesiumColor.withAlpha(fillAlpha),
          outlineColor: ambientKey
            ? ambientColor(this, ambientKey, cesiumColor, outlineAlpha, 0.3, dotOpacity)
            : cesiumColor.withAlpha(outlineAlpha),
          outlineWidth: ambientKey
            ? ambientOutlineWidth(this, ambientKey, outlineWidth, 1.5)
            : outlineWidth,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: showLabel ? {
          text: labelText,
          font: `${weight >= 0.5 ? 14 : 13}px DM Sans, sans-serif`,
          fillColor: Cesium.Color.WHITE.withAlpha(weight >= 0.5 ? 0.95 : 0.85),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -(pixelSize + 12)),
          // One fade for every label. The old split let anything over 28px stay at
          // 0.6 alpha at any zoom and draw through the Earth, so the biggest dots
          // were permanently shouting from the far side of the globe.
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.1, 1.2e7, 0.45),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 1.2e7, 0),
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          // Match the dot. At 0 the label depth-tests against terrain and sinks
          // into the ground while the dot it belongs to floats above it.
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        } : undefined,
        // No `description`: infoBox is disabled (core.js:130) and the click path
        // reads _newsData, not the entity. Building it cost eight escaped article
        // cards per cluster on every render and was never shown to anyone.
      })
      this._newsEntities.push(entity)
      clusterEvents.forEach(ev => this._newsEntityByEventIdx.set(ev._idx, entity))

      const worstThreat = clusterEvents.find(e => e.threat === "critical")?.threat
        || clusterEvents.find(e => e.threat === "high")?.threat
      if (worstThreat) {
        const threatColor = worstThreat === "critical"
          ? Cesium.Color.fromCssColorString("#f44336")
          : Cesium.Color.fromCssColorString("#ff5722")
        const ring = dataSource.entities.add({
          id: `news-threat-${lead._idx}`,
          position: Cesium.Cartesian3.fromDegrees(avgLng, avgLat, 0),
          ellipse: {
            semiMinorAxis: 30000,
            semiMajorAxis: 30000,
            material: threatColor.withAlpha(0.06),
            outline: true,
            outlineColor: threatColor.withAlpha(0.25),
            outlineWidth: 1,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._newsEntities.push(ring)
      }
    })

    if (ambient) commitAmbientLayer(this, "news")

    this._precomputeArcs(events)

    if (this._newsActiveTab === "articles") {
      this._renderNewsArticleList()
      this._setNewsDotOpacity(0.25)
    } else {
      this._setNewsDotOpacity(1.0)
    }
  }

  GlobeController.prototype._renderTimelineNews = function(events) {
    const dataSource = this.getNewsDataSource()
    dataSource.show = true
    this._newsArcData = []
    this._timelineNewsEntityMap = this._timelineNewsEntityMap || new Map()
    this._timelineNewsPulseMap = this._timelineNewsPulseMap || new Map()

    const sortedEvents = [...events].sort((a, b) => {
      const aTime = a?.time ? new Date(a.time).getTime() : 0
      const bTime = b?.time ? new Date(b.time).getTime() : 0
      if (bTime !== aTime) return bTime - aTime
      return stableTimelineNewsId(a).localeCompare(stableTimelineNewsId(b))
    })
    const nextEntityIds = new Set()
    const nextPulseIds = new Set()

    sortedEvents.forEach((ev, idx) => {
      const color = newsCategoryColor(ev.category)
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const alpha = Number.isFinite(ev.timelineAlpha) ? ev.timelineAlpha : 1
      const appear = Number.isFinite(ev.timelineAppear) ? ev.timelineAppear : 1
      const pulse = Number.isFinite(ev.timelinePulse) ? ev.timelinePulse : 0
      const title = ev.title || ev.name || "Untitled"
      const labelText = idx < 12 ? this._truncateNewsLabel(title, 36) : ""
      const sourceName = ev.source ? `${this._escapeHtml(ev.source)} · ` : ""
      const pointSize = (idx < 12 ? 13 : 9) * (0.78 + appear * 0.22)
      const baseId = stableTimelineNewsId(ev)
      const entityId = `timeline-news-${baseId}`
      const pulseId = `timeline-news-pulse-${baseId}`
      nextEntityIds.add(entityId)

      const entityConfig = {
        position: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 10),
        point: {
          pixelSize: pointSize,
          color: cesiumColor.withAlpha(0.88 * alpha),
          outlineColor: cesiumColor.withAlpha(0.35 * alpha),
          outlineWidth: (idx < 12 ? 3 : 2) + pulse * 2.5,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.1, 1e7, 0.45),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: labelText ? {
          text: labelText,
          font: "13px DM Sans, sans-serif",
          fillColor: Cesium.Color.WHITE.withAlpha(0.9 * alpha),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -20),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 6e6, 0),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 6e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        } : undefined,
        description: `<div style="font-family: 'DM Sans', sans-serif; max-width: 320px;">
          <div style="font-size: 11px; color: ${color}; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px;">${sourceName}${this._escapeHtml(ev.category || "news")}</div>
          <div style="font-size: 14px; font-weight: 600; margin-bottom: 6px; line-height: 1.3;">${this._escapeHtml(title)}</div>
          ${ev.time ? `<div style="font-size: 11px; color: #8892a4; margin-bottom: 4px;">${this._escapeHtml(ev.time)}</div>` : ""}
          <a href="${this._safeUrl(ev.url)}" target="_blank" rel="noopener" style="color: ${color}; font-size: 11px;">Read →</a>
        </div>`,
      }

      let entity = this._timelineNewsEntityMap.get(entityId)
      if (!entity) {
        entity = dataSource.entities.add({ id: entityId, ...entityConfig })
        this._timelineNewsEntityMap.set(entityId, entity)
      } else {
        entity.position = entityConfig.position
        entity.point = entityConfig.point
        entity.label = entityConfig.label
        entity.description = entityConfig.description
      }

      if (pulse > 0.08) {
        nextPulseIds.add(pulseId)
        const pulseProgress = 1 - pulse
        const pulseAlpha = 0.18 + pulse * 0.82
        const ringConfig = {
          position: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 0),
          ellipse: {
            semiMinorAxis: 16000 + pulseProgress * 190000,
            semiMajorAxis: 16000 + pulseProgress * 190000,
            material: cesiumColor.withAlpha(0.06 * pulseAlpha),
            outline: true,
            outlineColor: cesiumColor.withAlpha(0.9 * pulseAlpha),
            outlineWidth: 1.8 + pulse * 1.4,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        }

        let ring = this._timelineNewsPulseMap.get(pulseId)
        if (!ring) {
          ring = dataSource.entities.add({ id: pulseId, ...ringConfig })
          this._timelineNewsPulseMap.set(pulseId, ring)
        } else {
          ring.position = ringConfig.position
          ring.ellipse = ringConfig.ellipse
        }
      }
    })

    this._timelineNewsEntityMap.forEach((entity, id) => {
      if (nextEntityIds.has(id)) return
      dataSource.entities.remove(entity)
      this._timelineNewsEntityMap.delete(id)
    })
    this._timelineNewsPulseMap.forEach((entity, id) => {
      if (nextPulseIds.has(id)) return
      dataSource.entities.remove(entity)
      this._timelineNewsPulseMap.delete(id)
    })
    this._newsEntities = [
      ...this._timelineNewsEntityMap.values(),
      ...this._timelineNewsPulseMap.values(),
    ]

    this._renderRegionFlows()

    if (this._newsActiveTab === "articles") {
      this._renderNewsArticleList()
      this._setNewsDotOpacity(0.25)
    }
    this._requestRender()
  }

  GlobeController.prototype._getSourceLocation = function(url) {
    if (!url) return null
    let host
    try { host = new URL(url).hostname.replace(/^www\./, "") } catch { return null }

    const knownSources = {
      "nytimes.com": [40.76, -73.99, "New York"],
      "washingtonpost.com": [38.90, -77.04, "Washington DC"],
      "cnn.com": [33.75, -84.39, "Atlanta"],
      "foxnews.com": [40.76, -73.99, "New York"],
      "bbc.com": [51.52, -0.13, "London"],
      "bbc.co.uk": [51.52, -0.13, "London"],
      "dailymail.co.uk": [51.52, -0.13, "London"],
      "theguardian.com": [51.52, -0.13, "London"],
      "reuters.com": [51.52, -0.13, "London"],
      "aljazeera.com": [25.29, 51.53, "Doha"],
      "rt.com": [55.75, 37.62, "Moscow"],
      "russian.rt.com": [55.75, 37.62, "Moscow"],
      "lenta.ru": [55.75, 37.62, "Moscow"],
      "aif.ru": [55.75, 37.62, "Moscow"],
      "spiegel.de": [53.55, 9.99, "Hamburg"],
      "stern.de": [53.55, 9.99, "Hamburg"],
      "merkur.de": [48.14, 11.58, "Munich"],
      "lemonde.fr": [48.86, 2.35, "Paris"],
      "radiofrance.fr": [48.86, 2.35, "Paris"],
      "zonebourse.com": [48.86, 2.35, "Paris"],
      "ansa.it": [41.90, 12.50, "Rome"],
      "zazoom.it": [41.90, 12.50, "Rome"],
      "europapress.es": [40.42, -3.70, "Madrid"],
      "aa.com.tr": [39.93, 32.86, "Ankara"],
      "haberler.com": [41.01, 28.98, "Istanbul"],
      "malatyaguncel.com": [38.35, 38.31, "Malatya"],
      "birgun.net": [41.01, 28.98, "Istanbul"],
      "dunya.com": [41.01, 28.98, "Istanbul"],
      "inewsgr.com": [37.98, 23.73, "Athens"],
      "163.com": [30.27, 120.15, "Hangzhou"],
      "sina.com.cn": [31.23, 121.47, "Shanghai"],
      "baidu.com": [39.91, 116.40, "Beijing"],
      "baijiahao.baidu.com": [39.91, 116.40, "Beijing"],
      "china.com": [39.91, 116.40, "Beijing"],
      "81.cn": [39.91, 116.40, "Beijing"],
      "ltn.com.tw": [25.03, 121.57, "Taipei"],
      "yam.com": [25.03, 121.57, "Taipei"],
      "baomoi.com": [21.03, 105.85, "Hanoi"],
      "shorouknews.com": [30.04, 31.24, "Cairo"],
      "almasryalyoum.com": [30.04, 31.24, "Cairo"],
      "moneycontrol.com": [19.08, 72.88, "Mumbai"],
      "naslovi.net": [44.79, 20.47, "Belgrade"],
      "politika.rs": [44.79, 20.47, "Belgrade"],
      "24tv.ua": [50.45, 30.52, "Kyiv"],
      "mignews.com": [32.07, 34.77, "Tel Aviv"],
      "idnes.cz": [50.08, 14.44, "Prague"],
      "heraldcorp.com": [37.57, 126.98, "Seoul"],
      "etoday.co.kr": [37.57, 126.98, "Seoul"],
      "allafrica.com": [38.90, -77.04, "Washington DC"],
      "time.mk": [41.99, 21.43, "Skopje"],
      "lurer.com": [40.18, 44.51, "Yerevan"],
    }

    for (const [domain, loc] of Object.entries(knownSources)) {
      if (host === domain || host.endsWith("." + domain)) {
        return { lat: loc[0], lng: loc[1], city: loc[2] }
      }
    }

    const tldCountry = {
      de: [51.0, 9.0, "Germany"], fr: [46.0, 2.0, "France"], it: [42.8, 12.8, "Italy"],
      es: [40.0, -4.0, "Spain"], nl: [52.5, 5.8, "Netherlands"], be: [50.8, 4.0, "Belgium"],
      at: [47.5, 13.5, "Austria"], ch: [47.0, 8.0, "Switzerland"], se: [62.0, 15.0, "Sweden"],
      no: [62.0, 10.0, "Norway"], dk: [56.0, 10.0, "Denmark"], fi: [64.0, 26.0, "Finland"],
      pl: [52.0, 20.0, "Poland"], cz: [49.8, 15.5, "Czechia"], sk: [48.7, 19.5, "Slovakia"],
      hu: [47.0, 20.0, "Hungary"], ro: [46.0, 25.0, "Romania"], bg: [43.0, 25.0, "Bulgaria"],
      hr: [45.2, 15.5, "Croatia"], rs: [44.0, 21.0, "Serbia"], ua: [49.0, 32.0, "Ukraine"],
      ru: [55.75, 37.62, "Russia"], tr: [39.0, 35.0, "Turkey"], gr: [39.0, 22.0, "Greece"],
      pt: [39.5, -8.0, "Portugal"], ie: [53.0, -8.0, "Ireland"], gb: [51.52, -0.13, "UK"],
      uk: [51.52, -0.13, "UK"], in: [20.0, 77.0, "India"], cn: [39.91, 116.40, "China"],
      jp: [36.0, 138.0, "Japan"], kr: [37.57, 126.98, "S. Korea"], tw: [25.03, 121.57, "Taiwan"],
      au: [-25.0, 135.0, "Australia"], nz: [-42.0, 174.0, "NZ"], br: [-10.0, -55.0, "Brazil"],
      ar: [-34.0, -64.0, "Argentina"], mx: [23.0, -102.0, "Mexico"], za: [-29.0, 24.0, "S. Africa"],
      il: [32.07, 34.77, "Israel"], eg: [30.04, 31.24, "Egypt"], sa: [25.0, 45.0, "Saudi Arabia"],
      ae: [24.0, 54.0, "UAE"], pk: [30.0, 70.0, "Pakistan"], ir: [32.0, 53.0, "Iran"],
      mk: [41.99, 21.43, "N. Macedonia"], am: [40.18, 44.51, "Armenia"],
      ge: [42.0, 43.5, "Georgia"], az: [40.5, 47.5, "Azerbaijan"],
      vn: [21.03, 105.85, "Vietnam"], th: [15.0, 100.0, "Thailand"],
      my: [2.5, 112.5, "Malaysia"], sg: [1.4, 103.8, "Singapore"],
      ph: [13.0, 122.0, "Philippines"], id: [-5.0, 120.0, "Indonesia"],
      ca: [60.0, -95.0, "Canada"], co: [4.0, -72.0, "Colombia"],
    }

    const parts = host.split(".")
    let tld = parts[parts.length - 1]
    if (parts.length >= 3 && ["co", "com", "org", "net"].includes(parts[parts.length - 2])) {
      tld = parts[parts.length - 1]
    }

    const loc = tldCountry[tld]
    if (loc) return { lat: loc[0], lng: loc[1], city: loc[2] }

    return null
  }

  GlobeController.prototype._truncateNewsLabel = function(text, maxLen) {
    if (!text) return ""
    const clean = text.split(/\s*[|–—]\s*/)[0].trim()
    if (clean.length <= maxLen) return clean
    return clean.substring(0, maxLen - 1).trim() + "…"
  }

  GlobeController.prototype._precomputeArcs = function(events) {
    const arcMap = new Map()
    this._newsArcData = []

    events.forEach(ev => {
      const src = this._getSourceLocation(ev.url)
      if (!src) return
      if (Math.abs(src.lat - ev.lat) < 2 && Math.abs(src.lng - ev.lng) < 2) return

      let host
      try { host = new URL(ev.url).hostname.replace(/^www\./, "") } catch { return }

      const key = `${src.lat.toFixed(0)},${src.lng.toFixed(0)}→${ev.lat.toFixed(0)},${ev.lng.toFixed(0)}`
      if (!arcMap.has(key)) {
        arcMap.set(key, {
          srcLat: src.lat, srcLng: src.lng, srcCity: src.city,
          evtLat: ev.lat, evtLng: ev.lng, evtName: ev.name?.split(",")[0] || "",
          evtLocKey: `${ev.lat.toFixed(0)},${ev.lng.toFixed(0)}`,
          count: 0, articles: [],
        })
      }
      const entry = arcMap.get(key)
      entry.count++
      if (entry.articles.length < 15) {
        entry.articles.push({ domain: host, url: ev.url, name: ev.name, category: ev.category, tone: ev.tone })
      }
    })

    this._newsArcData = [...arcMap.values()].sort((a, b) => b.count - a.count)
    this._renderRegionFlows()
  }

  GlobeController.prototype._showClusterArcs = function(clusterLocKey) {
    this._clearNewsArcEntities()
    if (!clusterLocKey || !this._newsArcData?.length) return

    const Cesium = window.Cesium
    const dataSource = this.getNewsDataSource()
    const arcs = this._newsArcData.filter(a => a.evtLocKey === clusterLocKey)
    this._activeClusterArcs = arcs

    arcs.forEach((arc, idx) => {
      const alpha = Math.min(0.25 + arc.count * 0.1, 0.7)
      const width = Math.max(8, Math.min(1.5 + arc.count * 0.4, 12))
      const arcColor = Cesium.Color.fromCssColorString("#ffab40").withAlpha(alpha)

      const positions = this._slerpArc(arc.srcLat, arc.srcLng, arc.evtLat, arc.evtLng)
      if (positions.length < 2) return

      const entity = dataSource.entities.add({
        id: `news-arc-${idx}`,
        polyline: { positions, width, material: new Cesium.PolylineGlowMaterialProperty({ glowPower: 0.2, color: arcColor }) },
      })
      this._newsArcEntities.push(entity)

      const blobColor = Cesium.Color.fromCssColorString("#ffab40")
      const blob = dataSource.entities.add({
        id: `news-arc-blob-${idx}-0`,
        position: positions[0],
        point: {
          pixelSize: Math.max(5, Math.min(10, 4 + arc.count * 0.5)),
          color: blobColor.withAlpha(0.9),
          outlineColor: blobColor.withAlpha(0.3),
          outlineWidth: 2,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.2, 1e7, 0.4),
        },
      })
      this._newsArcEntities.push(blob)
      blob._blobArc = positions
      blob._blobPhase = (idx * 7.31) % 1.0
      blob._blobSpeed = 0.15

      const srcLabel = dataSource.entities.add({
        id: `news-arc-lbl-${idx}`,
        position: positions[0],
        label: {
          text: `${arc.srcCity} (${arc.count})`,
          font: "11px JetBrains Mono, monospace",
          fillColor: Cesium.Color.fromCssColorString("#ffab40").withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -8),
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1, 1e7, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1.2e7, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._newsArcEntities.push(srcLabel)
    })
  }

  GlobeController.prototype._slerpArc = function(lat1, lng1, lat2, lng2) {
    const Cesium = window.Cesium
    const oLat = lat1 * Math.PI / 180
    const oLng = lng1 * Math.PI / 180
    const tLat = lat2 * Math.PI / 180
    const tLng = lng2 * Math.PI / 180
    const SEGS = 30
    const positions = []
    for (let i = 0; i <= SEGS; i++) {
      const f = i / SEGS
      const d = Math.acos(Math.min(1, Math.sin(oLat) * Math.sin(tLat) + Math.cos(oLat) * Math.cos(tLat) * Math.cos(tLng - oLng)))
      if (d < 0.001) break
      const A = Math.sin((1 - f) * d) / Math.sin(d)
      const B = Math.sin(f * d) / Math.sin(d)
      const x = A * Math.cos(oLat) * Math.cos(oLng) + B * Math.cos(tLat) * Math.cos(tLng)
      const y = A * Math.cos(oLat) * Math.sin(oLng) + B * Math.cos(tLat) * Math.sin(tLng)
      const z = A * Math.sin(oLat) + B * Math.sin(tLat)
      const lat = Math.atan2(z, Math.sqrt(x * x + y * y)) * 180 / Math.PI
      const lng = Math.atan2(y, x) * 180 / Math.PI
      const lift = Math.sin(f * Math.PI) * (100000 + d * 800000)
      positions.push(Cesium.Cartesian3.fromDegrees(lng, lat, lift))
    }
    return positions
  }

  GlobeController.prototype._renderRegionFlows = function() {
    if (!this.hasNewsFeedContentTarget) return
    const regions = this.constructor.NEWS_REGIONS
    const regionNames = {
      "north-america": "N. America", "south-america": "S. America", europe: "Europe",
      "middle-east": "Middle East", africa: "Africa", "central-asia": "C. Asia",
      "east-asia": "E. Asia", "southeast-asia": "SE Asia", oceania: "Oceania",
    }

    const getRegion = (lat, lng) => {
      for (const [key, r] of Object.entries(regions)) {
        if (lat >= r.latMin && lat <= r.latMax && lng >= r.lngMin && lng <= r.lngMax) return key
      }
      return null
    }

    const flows = new Map()
    for (const arc of (this._newsArcData || [])) {
      const srcR = getRegion(arc.srcLat, arc.srcLng)
      const evtR = getRegion(arc.evtLat, arc.evtLng)
      if (!srcR || !evtR) continue
      const key = `${srcR}→${evtR}`
      if (!flows.has(key)) flows.set(key, { from: srcR, to: evtR, count: 0, articles: 0 })
      const f = flows.get(key)
      f.count++
      f.articles += arc.count
    }

    const sorted = [...flows.values()].sort((a, b) => b.articles - a.articles)
    const maxArticles = sorted[0]?.articles || 1

    if (this.hasNewsFeedCountTarget) {
      this.newsFeedCountTarget.textContent = `${sorted.length} flows`
    }

    if (sorted.length === 0) {
      this.newsFeedContentTarget.innerHTML = '<div style="padding:24px 14px;text-align:center;color:var(--gt-text-dim);font:500 11px var(--gt-mono);">No attention flows detected</div>'
      return
    }

    const regionColors = {
      "north-america": "#42a5f5", "south-america": "#66bb6a", europe: "#ab47bc",
      "middle-east": "#f44336", africa: "#ff9800", "central-asia": "#ffc107",
      "east-asia": "#26c6da", "southeast-asia": "#8d6e63", oceania: "#78909c",
    }

    const html = sorted.map((flow) => {
      const pct = Math.round((flow.articles / maxArticles) * 100)
      const fromColor = regionColors[flow.from] || "#90a4ae"
      const toColor = regionColors[flow.to] || "#90a4ae"
      return `<div class="nf-flow-row" data-action="click->globe#focusRegionFlow" data-flow-from="${flow.from}" data-flow-to="${flow.to}">
        <div class="nf-flow-header">
          <span class="nf-flow-region" style="color:${fromColor}">${regionNames[flow.from]}</span>
          <span class="nf-flow-arrow">→</span>
          <span class="nf-flow-region" style="color:${toColor}">${regionNames[flow.to]}</span>
          <span class="nf-flow-count">${flow.articles}</span>
        </div>
        <div class="nf-flow-bar-bg">
          <div class="nf-flow-bar" style="width:${pct}%;background:linear-gradient(90deg,${fromColor}88,${toColor}88);"></div>
        </div>
      </div>`
    }).join("")

    this.newsFeedContentTarget.innerHTML = html
  }

  GlobeController.prototype.focusRegionFlow = function(event) {
    const from = event.currentTarget.dataset.flowFrom
    const to = event.currentTarget.dataset.flowTo
    const regions = this.constructor.NEWS_REGIONS
    const getRegion = (lat, lng) => {
      for (const [key, r] of Object.entries(regions)) {
        if (lat >= r.latMin && lat <= r.latMax && lng >= r.lngMin && lng <= r.lngMax) return key
      }
      return null
    }

    this._clearNewsArcEntities()
    const Cesium = window.Cesium
    const dataSource = this.getNewsDataSource()

    const arcs = (this._newsArcData || []).filter(a =>
      getRegion(a.srcLat, a.srcLng) === from && getRegion(a.evtLat, a.evtLng) === to
    ).slice(0, 60)

    arcs.forEach((arc, idx) => {
      const alpha = Math.min(0.25 + arc.count * 0.1, 0.7)
      const width = Math.max(8, Math.min(1.5 + arc.count * 0.4, 12))
      const arcColor = Cesium.Color.fromCssColorString("#ffab40").withAlpha(alpha)

      const positions = this._slerpArc(arc.srcLat, arc.srcLng, arc.evtLat, arc.evtLng)
      if (positions.length < 2) return

      this._newsArcEntities.push(dataSource.entities.add({
        id: `news-arc-${idx}`,
        polyline: { positions, width, material: new Cesium.PolylineGlowMaterialProperty({ glowPower: 0.2, color: arcColor }) },
      }))

      const blob = dataSource.entities.add({
        id: `news-arc-blob-${idx}-0`,
        position: positions[0],
        point: {
          pixelSize: Math.max(5, Math.min(10, 4 + arc.count * 0.5)),
          color: Cesium.Color.fromCssColorString("#ffab40").withAlpha(0.9),
          outlineColor: Cesium.Color.fromCssColorString("#ffab40").withAlpha(0.3),
          outlineWidth: 2,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.2, 1e7, 0.4),
        },
      })
      this._newsArcEntities.push(blob)
      blob._blobArc = positions
      blob._blobPhase = (idx * 7.31) % 1.0
      blob._blobSpeed = 0.15
    })

    const rows = this.newsFeedContentTarget?.querySelectorAll(".nf-flow-row") || []
    rows.forEach(r => r.classList.toggle("nf-flow-row--active",
      r.dataset.flowFrom === from && r.dataset.flowTo === to))
  }

  // Scale one colour property by the layer opacity, against the colour the
  // entity was BUILT with rather than whatever the previous dim left behind.
  //
  // The old version assigned `alpha` outright. That flattened every static dot
  // to a single value on the first call -- and _renderNews calls this on every
  // render -- so the located/vague alphas (0.92 vs 0.3) never reached the
  // screen, and un-dimming restored them to a flat 1.0 rather than to their
  // real strength. Caching the base makes the dim reversible.
  const dimColor = (graphic, prop, alpha) => {
    const Cesium = window.Cesium
    if (!graphic || graphic[prop] instanceof Cesium.CallbackProperty) return
    const base = graphic._newsBaseColors || (graphic._newsBaseColors = {})
    if (!base[prop]) {
      const current = graphic[prop]?.getValue?.()
      if (!current) return
      base[prop] = Cesium.Color.clone(current)
    }
    const c = base[prop]
    graphic[prop] = new Cesium.Color(c.red, c.green, c.blue, c.alpha * alpha)
  }

  GlobeController.prototype._setNewsDotOpacity = function(alpha) {
    // Ambient points read this each frame inside their CallbackProperty;
    // overwriting their colour would replace the callback with a constant and
    // freeze the pulse. dimColor skips them for that reason.
    this._newsDotOpacity = alpha
    for (const entity of this._newsEntities) {
      dimColor(entity.point, "color", alpha)
      dimColor(entity.point, "outlineColor", alpha)
      dimColor(entity.label, "fillColor", alpha)
      dimColor(entity.label, "outlineColor", alpha)
      if (entity.ellipse) {
        // The threat ring is part of the news layer and has to fade with it.
        dimColor(entity.ellipse.material, "color", alpha)
        dimColor(entity.ellipse, "outlineColor", alpha)
      }
    }
    this._requestRender()
  }

  GlobeController.prototype._clearNewsEntities = function() {
    const ds = this.getNewsDataSource()
    this._newsEntities.forEach(e => ds.entities.remove(e))
    this._newsEntities = []
    this._newsEntityByEventIdx?.clear?.()
    clearAmbientLayer(this, "news")
    this._timelineNewsEntityMap?.clear?.()
    this._timelineNewsPulseMap?.clear?.()
    this._clearNewsArcEntities()
  }

  GlobeController.prototype._clearNewsArcEntities = function() {
    this._stopNewsArcBlobAnim()
    const ds = this.getNewsDataSource()
    ;(this._newsArcEntities || []).forEach(e => ds.entities.remove(e))
    this._newsArcEntities = []
  }

  GlobeController.prototype._stopNewsArcBlobAnim = function() {
    if (this._newsArcBlobRaf) {
      cancelAnimationFrame(this._newsArcBlobRaf)
      this._newsArcBlobRaf = null
    }
  }

  GlobeController.prototype._removeNewsBlobEntities = function() {
    const ds = this.getNewsDataSource()
    const kept = []
    for (const e of (this._newsArcEntities || [])) {
      if (e._blobArc) {
        ds.entities.remove(e)
      } else {
        kept.push(e)
      }
    }
    this._newsArcEntities = kept
  }
}

function stableTimelineNewsId(event) {
  if (event?.id != null && event.id !== "") return String(event.id)
  const parts = [
    event?.time || "",
    Number.isFinite(event?.lat) ? event.lat.toFixed(4) : "",
    Number.isFinite(event?.lng) ? event.lng.toFixed(4) : "",
    event?.title || event?.name || "",
  ]
  return parts.join("|")
}
