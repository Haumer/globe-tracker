import { getDataSource } from "../utils"

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
    if (this.newsVisible) {
      this.fetchNews()
      this._newsInterval = setInterval(() => this.fetchNews(), 900000)
      if (this.hasNewsArcControlsTarget) this.newsArcControlsTarget.style.display = ""
    } else {
      if (this._newsInterval) {
        clearInterval(this._newsInterval)
        this._newsInterval = null
      }
      this._clearNewsEntities()
      this._newsData = []
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

    const categoryColors = {
      conflict: "#f44336",
      unrest: "#ff9800",
      disaster: "#ff5722",
      health: "#e91e63",
      economy: "#ffc107",
      diplomacy: "#4caf50",
      other: "#90a4ae",
    }

    const clusters = new Map()
    events.forEach((ev, i) => {
      const key = `${ev.lat.toFixed(0)},${ev.lng.toFixed(0)}`
      if (!clusters.has(key)) clusters.set(key, [])
      clusters.get(key).push({ ...ev, _idx: i })
    })

    const clusterSizes = [...clusters.values()].map(c => c.length).sort((a, b) => b - a)
    const top3Threshold = clusterSizes[2] || 0

    clusters.forEach((clusterEvents) => {
      clusterEvents.sort((a, b) => (b.priority || Math.abs(b.tone)) - (a.priority || Math.abs(a.tone)))
      const lead = clusterEvents[0]
      const count = clusterEvents.length
      const color = categoryColors[lead.category] || "#90a4ae"
      const cesiumColor = Cesium.Color.fromCssColorString(color)

      const avgLat = clusterEvents.reduce((s, e) => s + e.lat, 0) / count
      const avgLng = clusterEvents.reduce((s, e) => s + e.lng, 0) / count

      const intensity = Math.min((lead.priority != null ? lead.priority : Math.abs(lead.tone)) / 10, 1)
      const coverageBoost = Math.min(Math.log2(count + 1) / 3, 1)
      let pixelSize = 6 + intensity * 6 + coverageBoost * 8

      if (clusterSizes.length >= 3 && count >= top3Threshold) {
        const rank = count >= clusterSizes[0] ? 0 : count >= clusterSizes[1] ? 1 : 2
        pixelSize = [48, 36, 28][rank]
      }

      const headline = this._truncateNewsLabel(lead.title || lead.name, pixelSize >= 28 ? 50 : 30)
      const labelText = count > 1 ? `${headline}  (+${count - 1})` : headline

      const descHtml = clusterEvents.slice(0, 8).map(ev => {
        const c = categoryColors[ev.category] || "#90a4ae"
        const sourceName = ev.publisher || ev.source
        return `<div style="margin-bottom: 10px; padding-bottom: 8px; border-bottom: 1px solid rgba(255,255,255,0.05);">
          <div style="font-size: 11px; color: ${c}; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 2px;">${this._escapeHtml(ev.category)}${sourceName ? " · " + this._escapeHtml(sourceName) : ""}</div>
          <div style="font-size: 13px; font-weight: 600; margin-bottom: 4px; line-height: 1.3;">${this._escapeHtml(ev.title || ev.name || "Unknown")}</div>
          ${ev.name && ev.title ? "<div style=\"font-size: 11px; color: #8892a4; margin-bottom: 4px;\">" + this._escapeHtml(ev.name) + "</div>" : ""}
          <div style="font-size: 11px; color: #aaa;">Tone: ${ev.tone} · ${this._escapeHtml(ev.level)}</div>
          <a href="${this._safeUrl(ev.url)}" target="_blank" rel="noopener" style="color: ${c}; font-size: 11px;">Read →</a>
        </div>`
      }).join("")
      const moreNote = count > 8 ? `<div style="font-size: 11px; color: #6b7a8d;">+ ${count - 8} more stories</div>` : ""

      const entity = dataSource.entities.add({
        id: `news-${lead._idx}`,
        position: Cesium.Cartesian3.fromDegrees(avgLng, avgLat, 10),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85 + coverageBoost * 0.15),
          outlineColor: cesiumColor.withAlpha(0.3 + coverageBoost * 0.4),
          outlineWidth: 2 + Math.floor(coverageBoost * 4),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: labelText,
          font: `${pixelSize >= 28 ? 15 : pixelSize >= 20 ? 14 : 13}px DM Sans, sans-serif`,
          fillColor: Cesium.Color.WHITE.withAlpha(pixelSize >= 28 ? 0.95 : 0.85),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: pixelSize >= 28 ? 4 : 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -(pixelSize + 12)),
          scaleByDistance: pixelSize >= 28
            ? new Cesium.NearFarScalar(1e5, 1.2, 1.5e7, 0.5)
            : new Cesium.NearFarScalar(1e5, 1, 5e6, 0),
          translucencyByDistance: pixelSize >= 28
            ? new Cesium.NearFarScalar(1e5, 1.0, 1.5e7, 0.6)
            : new Cesium.NearFarScalar(1e5, 1.0, 5e6, 0),
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: pixelSize >= 28 ? Number.POSITIVE_INFINITY : 0,
        },
        description: `<div style="font-family: 'DM Sans', sans-serif; max-width: 380px;">
          <div style="font-size: 12px; color: #6b7a8d; margin-bottom: 8px;">${count} stories in this area</div>
          ${descHtml}${moreNote}
        </div>`,
      })
      this._newsEntities.push(entity)

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

    this._precomputeArcs(events)

    if (this._newsActiveTab === "articles") {
      this._renderNewsArticleList()
      this._setNewsDotOpacity(0.25)
    }
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

  GlobeController.prototype._setNewsDotOpacity = function(alpha) {
    const Cesium = window.Cesium
    for (const entity of this._newsEntities) {
      if (entity.point) {
        const c = entity.point.color?.getValue()
        if (c) entity.point.color = new Cesium.Color(c.red, c.green, c.blue, alpha)
        const oc = entity.point.outlineColor?.getValue()
        if (oc) entity.point.outlineColor = new Cesium.Color(oc.red, oc.green, oc.blue, alpha * 0.5)
      }
      if (entity.label) {
        const fc = entity.label.fillColor?.getValue()
        if (fc) entity.label.fillColor = new Cesium.Color(fc.red, fc.green, fc.blue, alpha)
      }
    }
    this._requestRender()
  }

  GlobeController.prototype._clearNewsEntities = function() {
    const ds = this.getNewsDataSource()
    this._newsEntities.forEach(e => ds.entities.remove(e))
    this._newsEntities = []
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
