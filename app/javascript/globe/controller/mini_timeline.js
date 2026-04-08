export function applyMiniTimelineMethods(GlobeController) {

  const EVENT_COLORS = {
    earthquake: "#ff7043",
    natural_event: "#5c6bc0",
    news: "#66bb6a",
    gps_jamming: "#ff9800",
    internet_outage: "#ab47bc",
  }

  const ANOMALY_COLORS = {
    emergency_flight: "#f44336",
    military_spike: "#ef5350",
    new_jamming: "#ff9800",
    major_earthquake: "#ff7043",
  }

  GlobeController.prototype._startMiniTimeline = function() {
    this._miniTimelineEvents = []
    this._anomalies = []
    this._fetchMiniTimeline()
    this._fetchAnomalies()
    this._miniTimelineInterval = setInterval(() => this._fetchMiniTimeline(), 60000)
    this._anomalyInterval = setInterval(() => this._fetchAnomalies(), 120000)
  }

  GlobeController.prototype._stopMiniTimeline = function() {
    if (this._miniTimelineInterval) { clearInterval(this._miniTimelineInterval); this._miniTimelineInterval = null }
    if (this._anomalyInterval) { clearInterval(this._anomalyInterval); this._anomalyInterval = null }
  }

  // ── Timeline events (24h) ─────────────────────────────────

  GlobeController.prototype._fetchMiniTimeline = async function() {
    if (this._timelineActive) return
    try {
      const now = new Date()
      const from = new Date(now - 24 * 60 * 60 * 1000)
      const types = "earthquake,natural_event"
      const resp = await fetch(`/api/playback/events?from=${from.toISOString()}&to=${now.toISOString()}&types=${types}`)
      if (!resp.ok) return
      this._miniTimelineEvents = await resp.json()
      this._renderMiniTimeline()
    } catch (e) {
      console.warn("Mini-timeline fetch failed:", e)
    }
  }

  // ── Anomaly detection ─────────────────────────────────────

  GlobeController.prototype._fetchAnomalies = async function() {
    if (this._timelineActive) return
    try {
      const resp = await fetch("/api/anomalies")
      if (!resp.ok) return
      this._anomalies = await resp.json()
      this._renderMiniTimeline()
      this._renderAnomalyIndicator()
    } catch (e) {
      console.warn("Anomaly fetch failed:", e)
    }
  }

  GlobeController.prototype._renderAnomalyIndicator = function() {
    const anomalies = this._anomalies || []
    const countEl = document.getElementById("mt-count")
    if (!countEl) return

    const events = this._miniTimelineEvents || []
    if (anomalies.length > 0) {
      const top = anomalies[0]
      countEl.innerHTML = `<span style="color:${top.color};">⚠ ${anomalies.length}</span> · ${events.length} events`
    } else {
      countEl.textContent = `${events.length} events`
    }
  }

  // ── Render ────────────────────────────────────────────────

  GlobeController.prototype._renderMiniTimeline = function() {
    if (!this.hasMiniTimelineDotsTarget) return

    const container = this.miniTimelineDotsTarget
    const events = this._miniTimelineEvents || []
    const anomalies = this._anomalies || []
    const now = Date.now()
    const windowMs = 24 * 60 * 60 * 1000
    const start = now - windowMs
    const width = container.offsetWidth || 320

    let html = ""

    // Hour markers
    for (let h = 0; h < 24; h += 6) {
      const x = (h / 24) * 100
      html += `<div style="position:absolute;left:${x}%;top:0;width:1px;height:100%;background:#333;"></div>`
    }

    // "Now" marker at far right
    html += `<div style="position:absolute;right:0;top:0;width:2px;height:100%;background:#4fc3f7;opacity:0.5;"></div>`

    // Cluster events into pixel buckets
    const bucketWidth = 4
    const buckets = new Map()

    events.forEach(ev => {
      if (!ev.time || !ev.lat) return
      const t = new Date(ev.time).getTime()
      const pct = ((t - start) / windowMs) * 100
      if (pct < 0 || pct > 100) return

      const px = Math.round((pct / 100) * width)
      const bucketKey = Math.floor(px / bucketWidth)

      if (!buckets.has(bucketKey)) {
        buckets.set(bucketKey, { pct, events: [], maxMag: 0, type: ev.type })
      }
      const bucket = buckets.get(bucketKey)
      bucket.events.push(ev)
      if (ev.mag && ev.mag > bucket.maxMag) {
        bucket.maxMag = ev.mag
        bucket.type = ev.type
      }
      const priority = { earthquake: 4, gps_jamming: 3, natural_event: 2, news: 1 }
      if ((priority[ev.type] || 0) > (priority[bucket.type] || 0)) {
        bucket.type = ev.type
      }
    })

    for (const [, bucket] of buckets) {
      const color = EVENT_COLORS[bucket.type] || "#888"
      const count = bucket.events.length
      const size = Math.min(4 + count, 12)
      const opacity = Math.min(0.5 + count * 0.15, 1)
      const top = 8 - size / 2
      const firstEv = bucket.events[0]
      html += `<div class="mt-dot" style="position:absolute;left:${bucket.pct}%;top:${top}px;width:${size}px;height:${size}px;border-radius:50%;background:${color};opacity:${opacity};pointer-events:all;cursor:pointer;" data-mt-lat="${firstEv.lat}" data-mt-lng="${firstEv.lng}" data-mt-title="${(firstEv.title || firstEv.name || bucket.type).replace(/"/g, '&quot;')}" data-mt-type="${bucket.type}" data-mt-count="${count}"></div>`
    }

    // Anomaly pips — small vertical ticks along the right edge, color-coded by type
    const maxAnomalies = Math.min(anomalies.length, 16)
    const pipWidth = 3
    const pipSpacing = Math.max(1, Math.floor(60 / maxAnomalies))
    for (let i = 0; i < maxAnomalies; i++) {
      const a = anomalies[i]
      if (!a.lat) continue
      const color = ANOMALY_COLORS[a.type] || a.color || "#f44336"
      const pipHeight = Math.min(4 + Math.round(a.severity * 0.8), 12)
      const top = 14 - pipHeight
      const rightPct = 97 - i * pipSpacing
      html += `<div class="mt-dot mt-anomaly" style="position:absolute;left:${rightPct}%;top:${top}px;width:${pipWidth}px;height:${pipHeight}px;border-radius:1px;background:${color};opacity:0.9;pointer-events:all;cursor:pointer;" data-mt-lat="${a.lat}" data-mt-lng="${a.lng}" data-mt-title="${(a.title || a.type).replace(/"/g, '&quot;')}" data-mt-type="${a.type}" data-mt-count="1"></div>`
    }

    container.innerHTML = html
    this._renderAnomalyIndicator()
  }

  GlobeController.prototype.miniTimelineClick = function(event) {
    const dot = event.target.closest(".mt-dot")
    if (!dot) return

    const lat = parseFloat(dot.dataset.mtLat)
    const lng = parseFloat(dot.dataset.mtLng)
    if (isNaN(lat) || isNaN(lng)) return

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 2000000),
      duration: 1.5,
    })

    const title = dot.dataset.mtTitle
    const count = parseInt(dot.dataset.mtCount)
    const label = count > 1 ? `${title} (+${count - 1} more)` : title
    this._toast(label)
    setTimeout(() => this._toastHide(), 3000)
  }
}
