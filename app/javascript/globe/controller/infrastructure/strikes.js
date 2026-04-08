import { getDataSource, cachedColor, LABEL_DEFAULTS } from "globe/utils"

function createStrikeIcon(confidence) {
  const size = 28
  const canvas = document.createElement("canvas")
  canvas.width = size; canvas.height = size
  const ctx = canvas.getContext("2d")
  const cx = size / 2, cy = size / 2

  // Color by confidence level
  const colors = {
    verified: [76, 175, 80],   // green — GeoConfirmed verified
    high:     [224, 64, 251],  // magenta
    medium:   [224, 64, 251],
    low:      [224, 64, 251],
  }
  const [r, g, b] = colors[confidence] || colors.low
  const alpha = confidence === "verified" ? 1.0 : confidence === "high" ? 1.0 : confidence === "medium" ? 0.8 : 0.5

  // Outer ring
  ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`
  ctx.lineWidth = 2
  ctx.beginPath()
  ctx.arc(cx, cy, 10, 0, Math.PI * 2)
  ctx.stroke()

  // Crosshairs
  ctx.lineWidth = 1.5
  ctx.beginPath()
  ctx.moveTo(cx, 2); ctx.lineTo(cx, 8)
  ctx.moveTo(cx, size - 8); ctx.lineTo(cx, size - 2)
  ctx.moveTo(2, cy); ctx.lineTo(8, cy)
  ctx.moveTo(size - 8, cy); ctx.lineTo(size - 2, cy)
  ctx.stroke()

  // Center dot — filled for verified
  if (confidence === "verified") {
    ctx.fillStyle = `rgba(${r}, ${g}, ${b}, 1.0)`
    ctx.beginPath()
    ctx.arc(cx, cy, 4, 0, Math.PI * 2)
    ctx.fill()
  } else {
    ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`
    ctx.beginPath()
    ctx.arc(cx, cy, 2.5, 0, Math.PI * 2)
    ctx.fill()
  }

  return canvas.toDataURL()
}

function createGeoconfirmedIcon() {
  const size = 24
  const canvas = document.createElement("canvas")
  canvas.width = size; canvas.height = size
  const ctx = canvas.getContext("2d")
  const cx = size / 2, cy = size / 2

  // Filled circle with location dot style — orange/amber
  ctx.fillStyle = "rgba(255, 152, 0, 0.15)"
  ctx.beginPath()
  ctx.arc(cx, cy, 10, 0, Math.PI * 2)
  ctx.fill()

  ctx.strokeStyle = "rgba(255, 152, 0, 0.7)"
  ctx.lineWidth = 1.5
  ctx.beginPath()
  ctx.arc(cx, cy, 10, 0, Math.PI * 2)
  ctx.stroke()

  // Inner dot
  ctx.fillStyle = "rgba(255, 152, 0, 0.9)"
  ctx.beginPath()
  ctx.arc(cx, cy, 3, 0, Math.PI * 2)
  ctx.fill()

  return canvas.toDataURL()
}

function strikeDetectionKind(strike) {
  if (strike?.detectionKind) return strike.detectionKind
  if (strike?.strikeConfidence === "verified" || strike?.gcMatch) return "verified_strike"
  return "heat_signature"
}

function isVerifiedStrike(strike) {
  return strikeDetectionKind(strike) === "verified_strike"
}

function normalizedStrikeConfidence(strike) {
  if (strike?.strikeConfidence === "verified") return "verified"
  if (strike?.strikeConfidence === "high") return "high"
  if (strike?.strikeConfidence === "medium") return "medium"
  if (strike?.strikeConfidence === "low") return "low"
  return isVerifiedStrike(strike) ? "verified" : "low"
}

const SAT_NORAD = {
  "Suomi NPP": 37849, "NOAA-20": 43013, "NOAA-21": 54234,
  "Terra": 25994, "Aqua": 27424,
}

export function applyStrikesMethods(GlobeController) {
  GlobeController.prototype.getStrikesDataSource = function() {
    return getDataSource(this.viewer, this._ds, "strikes")
  }

  GlobeController.prototype._verifiedStrikesLayerVisible = function() {
    return this.hasVerifiedStrikesToggleTarget ? this.verifiedStrikesVisible : this.strikesVisible
  }

  GlobeController.prototype._heatSignaturesLayerVisible = function() {
    return this.hasHeatSignaturesToggleTarget ? this.heatSignaturesVisible : this.strikesVisible
  }

  GlobeController.prototype._strikeSignalsVisible = function() {
    return this._verifiedStrikesLayerVisible() || this._heatSignaturesLayerVisible()
  }

  GlobeController.prototype._syncStrikeSignalsVisibility = function() {
    this.strikesVisible = this._strikeSignalsVisible()
    if (this.hasStrikesToggleTarget) this.strikesToggleTarget.checked = this.strikesVisible
  }

  GlobeController.prototype.toggleVerifiedStrikes = function() {
    this.verifiedStrikesVisible = this.hasVerifiedStrikesToggleTarget && this.verifiedStrikesToggleTarget.checked
    this._handleStrikeLayerToggle()
  }

  GlobeController.prototype.toggleHeatSignatures = function() {
    this.heatSignaturesVisible = this.hasHeatSignaturesToggleTarget && this.heatSignaturesToggleTarget.checked
    this._handleStrikeLayerToggle()
  }

  GlobeController.prototype.toggleStrikes = function() {
    const enabled = this.hasStrikesToggleTarget && this.strikesToggleTarget.checked
    if (this.hasVerifiedStrikesToggleTarget) this.verifiedStrikesToggleTarget.checked = enabled
    if (this.hasHeatSignaturesToggleTarget) this.heatSignaturesToggleTarget.checked = enabled
    this.verifiedStrikesVisible = enabled
    this.heatSignaturesVisible = enabled
    this._handleStrikeLayerToggle()
  }

  GlobeController.prototype._handleStrikeLayerToggle = function() {
    const wasVisible = this.strikesVisible
    this._syncStrikeSignalsVisibility()

    if (this._timelineActive) {
      if (!this.strikesVisible) this._clearStrikeEntities()
      this._timelineOnLayerToggle?.()
    } else if (this.strikesVisible) {
      if (!wasVisible) {
        this.fetchStrikes()
      } else {
        this.renderStrikes()
      }

      if (!this._strikesInterval) {
        this._strikesInterval = setInterval(() => {
          if (this._strikeSignalsVisible()) this.fetchStrikes()
        }, 300000)
      }
    } else {
      this._clearStrikeEntities()
      if (this._strikesInterval) { clearInterval(this._strikesInterval); this._strikesInterval = null }
    }

    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchStrikes = async function() {
    this._toast("Loading strike layers...")
    try {
      const resp = await fetch("/api/strikes")
      if (!resp.ok) return
      const data = await resp.json()

      // Handle both old array format and new {firms, geoconfirmed} format
      if (Array.isArray(data)) {
        // Legacy format
        this._strikeDetections = data.map(r => ({
          id: r[0], lat: r[1], lng: r[2], brightness: r[3],
          confidence: r[4], satellite: r[5], instrument: r[6],
          frp: r[7], daynight: r[8], time: r[9],
          strikeConfidence: r[10] || "low", clusterSize: r[11] || 0,
          detectionKind: r[12] ? "verified_strike" : "heat_signature",
        }))
        this._gcDetections = []
      } else {
        this._strikeDetections = (data.firms || []).map(r => ({
          id: r[0], lat: r[1], lng: r[2], brightness: r[3],
          confidence: r[4], satellite: r[5], instrument: r[6],
          frp: r[7], daynight: r[8], time: r[9],
          strikeConfidence: r[10] || "low", clusterSize: r[11] || 0,
          gcMatch: r[12] || null,
          detectionKind: r[13] || (r[12] ? "verified_strike" : "heat_signature"),
        }))
        this._gcDetections = (data.geoconfirmed || []).map(r => ({
          id: r[0], lat: r[1], lng: r[2], title: r[3],
          region: r[4], time: r[5], sourceUrls: r[6] || [],
          description: r[7], geoUrls: r[8] || [],
          detectionKind: "verified_strike",
        }))
      }

      this.renderStrikes()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch strikes:", e)
    }
  }

  GlobeController.prototype.renderStrikes = function() {
    this._clearStrikeEntities()
    if (!this._strikeSignalsVisible()) return

    const Cesium = window.Cesium
    const dataSource = this.getStrikesDataSource()
    const bounds = this._timelineActive && !(this.hasActiveFilter && this.hasActiveFilter())
      ? null
      : this.getViewportBounds()
    const showVerifiedStrikes = this._verifiedStrikesLayerVisible()
    const showHeatSignatures = this._heatSignaturesLayerVisible()
    const firmsColor = cachedColor("#e040fb")
    const verifiedColor = cachedColor("#4caf50")

    dataSource.entities.suspendEvents()

    // ── Render FIRMS detections ──────────────────────────────
    if (this._strikeDetections?.length) {
      this._strikeDetections.forEach(s => {
        if (bounds && (s.lat < bounds.lamin || s.lat > bounds.lamax || s.lng < bounds.lomin || s.lng > bounds.lomax)) return
        if (this.hasActiveFilter && this.hasActiveFilter() && !this.pointPassesFilter(s.lat, s.lng)) return

        const frp = s.frp || 1
        const alpha = Number.isFinite(s.timelineAlpha) ? s.timelineAlpha : 1
        const pulse = Number.isFinite(s.timelinePulse) ? s.timelinePulse : 0
        const timelinePulseOnly = this._timelineActive && Number.isFinite(s.timelinePulse)
        const isVerified = isVerifiedStrike(s)
        if ((isVerified && !showVerifiedStrikes) || (!isVerified && !showHeatSignatures)) return
        const confidence = normalizedStrikeConfidence(s)
        const color = isVerified ? verifiedColor : firmsColor
        const confScale = isVerified ? 1.4 : confidence === "high" ? 1.3 : confidence === "medium" ? 1.0 : 0.7

        // Glow ring
        if ((timelinePulseOnly && pulse > 0.08) || (frp > 10 && confidence !== "low")) {
          const pulseProgress = 1 - pulse
          const pulseAlpha = 0.18 + pulse * 0.82
          const staticRadius = Math.min(2000 + frp * 50, 15000)
          const ringRadius = timelinePulseOnly
            ? 8000 + pulseProgress * 140000
            : staticRadius
          const ring = dataSource.entities.add({
            id: `strike-ring-${s.id}`,
            position: Cesium.Cartesian3.fromDegrees(s.lng, s.lat, 0),
            ellipse: {
              semiMinorAxis: ringRadius,
              semiMajorAxis: ringRadius,
              material: color.withAlpha(timelinePulseOnly ? (0.08 * pulseAlpha) : ((isVerified ? 0.15 : 0.1) * alpha)),
              outline: true,
              outlineColor: color.withAlpha(timelinePulseOnly ? (0.95 * pulseAlpha) : ((isVerified ? 0.4 : 0.3) * alpha)),
              outlineWidth: timelinePulseOnly ? (1.8 + pulse * 1.2) : 1,
              height: 0,
              heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
              classificationType: Cesium.ClassificationType.BOTH,
            },
          })
          this._strikeEntities.push(ring)
        }

        if (!this._strikeIcons) this._strikeIcons = {}
        const iconKey = isVerified ? "verified" : confidence
        if (!this._strikeIcons[iconKey]) this._strikeIcons[iconKey] = createStrikeIcon(iconKey)

        const entity = dataSource.entities.add({
          id: `strike-${s.id}`,
          position: Cesium.Cartesian3.fromDegrees(s.lng, s.lat, 10),
          billboard: {
            image: this._strikeIcons[iconKey],
            color: Cesium.Color.WHITE.withAlpha(alpha),
            scale: confScale,
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.3),
            heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        })
        this._strikeEntities.push(entity)
      })
    }

    // ── Render standalone GeoConfirmed events ────────────────
    if (showVerifiedStrikes && this._gcDetections?.length) {
      if (!this._gcIcon) this._gcIcon = createGeoconfirmedIcon()

      this._gcDetections.forEach(gc => {
        if (bounds && (gc.lat < bounds.lamin || gc.lat > bounds.lamax || gc.lng < bounds.lomin || gc.lng > bounds.lomax)) return
        if (this.hasActiveFilter && this.hasActiveFilter() && !this.pointPassesFilter(gc.lat, gc.lng)) return
        const alpha = Number.isFinite(gc.timelineAlpha) ? gc.timelineAlpha : 1
        const pulse = Number.isFinite(gc.timelinePulse) ? gc.timelinePulse : 0

        if (this._timelineActive && pulse > 0.08) {
          const pulseProgress = 1 - pulse
          const pulseAlpha = 0.18 + pulse * 0.82
          const ring = dataSource.entities.add({
            id: `gc-ring-${gc.id}`,
            position: Cesium.Cartesian3.fromDegrees(gc.lng, gc.lat, 0),
            ellipse: {
              semiMinorAxis: 9000 + pulseProgress * 150000,
              semiMajorAxis: 9000 + pulseProgress * 150000,
              material: verifiedColor.withAlpha(0.08 * pulseAlpha),
              outline: true,
              outlineColor: verifiedColor.withAlpha(0.95 * pulseAlpha),
              outlineWidth: 1.8 + pulse * 1.2,
              height: 0,
              heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
              classificationType: Cesium.ClassificationType.BOTH,
            },
          })
          this._strikeEntities.push(ring)
        }

        const entity = dataSource.entities.add({
          id: `gc-${gc.id}`,
          position: Cesium.Cartesian3.fromDegrees(gc.lng, gc.lat, 10),
          billboard: {
            image: this._gcIcon,
            color: Cesium.Color.WHITE.withAlpha(alpha),
            scale: 1.0,
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1.1, 8e6, 0.3),
            heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        })
        this._strikeEntities.push(entity)
      })
    }

    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearStrikeEntities = function() {
    const ds = this._ds["strikes"]
    if (ds) {
      ds.entities.suspendEvents()
      this._strikeEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
      this._requestRender()
    }
    this._strikeEntities = []
  }

  GlobeController.prototype.showStrikeDetail = function(s, options = {}) {
    if (this._showCompactEntityDetail?.("strike", s, options)) return

    const date = s.time ? new Date(s.time) : null
    const ago = date ? this._timeAgo(date) : "Unknown"
    const timeStr = date ? date.toUTCString().replace("GMT", "UTC") : "Unknown"

    const noradId = SAT_NORAD[s.satellite]
    const satLink = noradId
      ? `<button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;"
           data-action="click->globe#flyToSatellite" data-norad="${noradId}">
           <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Track ${this._escapeHtml(s.satellite)}
         </button>`
      : ""

    // GeoConfirmed corroboration badge
    const gcMatch = s.gcMatch
    const gcHtml = gcMatch ? `
      <div style="margin:8px 0;padding:8px 10px;background:rgba(76,175,80,0.08);border:1px solid rgba(76,175,80,0.25);border-radius:4px;">
        <div style="font:600 9px var(--gt-mono);color:#4caf50;letter-spacing:1px;margin-bottom:4px;">
          <i class="fa-solid fa-location-dot" style="margin-right:4px;"></i>GEOCONFIRMED VERIFIED
        </div>
        <div style="font:400 10px var(--gt-body);color:rgba(200,210,225,0.8);line-height:1.4;">
          ${this._escapeHtml((gcMatch.title || "Verified strike").substring(0, 120))}
        </div>
        ${gcMatch.posted_at ? `<div style="font:400 9px var(--gt-mono);color:rgba(200,210,225,0.35);margin-top:3px;">Posted ${this._timeAgo(new Date(gcMatch.posted_at))}</div>` : ""}
        ${gcMatch.source_url ? `<a href="${this._safeUrl(gcMatch.source_url)}" target="_blank" rel="noopener" style="display:inline-block;margin-top:4px;font:500 9px var(--gt-mono);color:#4caf50;text-decoration:none;">View source <i class="fa-solid fa-arrow-up-right-from-square" style="font-size:8px;margin-left:3px;"></i></a>` : ""}
      </div>
    ` : ""

    // Find nearby conflict/strike news
    const nearbyNews = (this._newsData || []).filter(n =>
      (n.category === "conflict" || n.category === "terror") &&
      Math.abs(n.lat - s.lat) < 3.0 && Math.abs(n.lng - s.lng) < 3.0
    ).slice(0, 5)

    const newsHtml = nearbyNews.length > 0 ? `
      <div style="margin-top:10px;padding-top:8px;border-top:1px solid rgba(255,255,255,0.08);">
        <div style="font:600 9px var(--gt-mono);color:#e040fb;letter-spacing:1px;margin-bottom:6px;">RELATED REPORTS</div>
        ${nearbyNews.map(n => {
          const nTime = n.time ? this._timeAgo(new Date(n.time)) : ""
          return `<a href="${this._safeUrl(n.url)}" target="_blank" rel="noopener" style="display:block;padding:5px 0;color:rgba(200,210,225,0.85);text-decoration:none;font-size:10px;line-height:1.3;border-bottom:1px solid rgba(255,255,255,0.04);">
            ${this._escapeHtml((n.title || "").length > 85 ? n.title.substring(0, 83) + "…" : (n.title || ""))}
            <div style="color:rgba(200,210,225,0.4);font-size:9px;margin-top:1px;">${this._escapeHtml(((n.publisher || n.source || "")).replace(/^GN:\s*/, ""))}${nTime ? " · " + nTime : ""}</div>
          </a>`
        }).join("")}
      </div>
    ` : ""

    // Check if near known infrastructure
    const nearbyInfra = []
    if (this._powerPlantAll) {
      const nearPlants = this._powerPlantAll.filter(p =>
        Math.abs(p.lat - s.lat) < 0.5 && Math.abs(p.lng - s.lng) < 0.5
      ).slice(0, 3)
      nearPlants.forEach(p => {
        nearbyInfra.push(`<span style="color:#fdd835;"><i class="fa-solid fa-bolt" style="margin-right:3px;"></i>${this._escapeHtml(p.name)} (${p.fuel}, ${p.capacity || "?"} MW)</span>`)
      })
    }

    const infraHtml = nearbyInfra.length > 0 ? `
      <div style="margin-top:8px;padding:5px 8px;background:rgba(253,216,53,0.08);border:1px solid rgba(253,216,53,0.2);border-radius:4px;">
        <div style="font:600 9px var(--gt-mono);color:#fdd835;letter-spacing:0.5px;margin-bottom:4px;">NEARBY INFRASTRUCTURE</div>
        ${nearbyInfra.map(h => `<div style="font:400 10px var(--gt-mono);margin:2px 0;">${h}</div>`).join("")}
      </div>
    ` : ""

    const isVerified = isVerifiedStrike(s)
    const confidence = s.strikeConfidence
    const confColor = isVerified ? "#4caf50" : "#e040fb"
    const confLabel = isVerified ? "VERIFIED STRIKE — GeoConfirmed report + satellite heat signature" :
      confidence === "high" ? "HIGH CONFIDENCE HEAT SIGNATURE — clustered thermal detections + nearby conflict reporting" :
      confidence === "medium" ? ("MEDIUM CONFIDENCE HEAT SIGNATURE — " + (s.clusterSize >= 2 ? "clustered thermal detections" : "nearby conflict reporting")) :
      confidence === "low" ? "LOW CONFIDENCE HEAT SIGNATURE — isolated thermal anomaly" :
      "THERMAL SIGNATURE — NASA FIRMS satellite heat detection"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${confColor};">
        <i class="fa-solid fa-crosshairs" style="margin-right:6px;"></i>${isVerified ? "Verified Strike" : "Heat Signature"}
      </div>
      <div style="margin:4px 0 8px;padding:4px 8px;background:rgba(${isVerified ? "76,175,80" : "224,64,251"},0.1);border:1px solid rgba(${isVerified ? "76,175,80" : "224,64,251"},0.3);border-radius:4px;font:500 9px var(--gt-mono);color:${confColor};letter-spacing:0.5px;">
        ${confLabel}
      </div>
      <div class="detail-country">${s.lat.toFixed(3)}°, ${s.lng.toFixed(3)}°</div>
      ${gcHtml}
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Fire Power</span>
          <span class="detail-value">${s.frp ? s.frp.toFixed(1) + " MW" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Brightness</span>
          <span class="detail-value">${s.brightness ? s.brightness.toFixed(1) + " K" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Day/Night</span>
          <span class="detail-value">${s.daynight === "D" ? "Day" : "Night"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Detected by</span>
          <span class="detail-value" style="color:#ce93d8;">${this._escapeHtml(s.satellite || "Unknown")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Time</span>
          <span class="detail-value">${ago}</span>
        </div>
        ${s.clusterSize > 0 ? `<div class="detail-field">
          <span class="detail-label">Cluster</span>
          <span class="detail-value" style="color:#e040fb;">${s.clusterSize + 1} detections nearby</span>
        </div>` : ""}
      </div>
      ${infraHtml}
      ${satLink}
      ${newsHtml}
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: NASA FIRMS heat detection (${this._escapeHtml(s.instrument || "VIIRS")} on ${this._escapeHtml(s.satellite || "Unknown")})${isVerified ? " + GeoConfirmed" : ""}</div>
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("fire_hotspot", s.lat, s.lng, { satellite: s.satellite })
  }

  GlobeController.prototype._strikeMediaDescriptor = function(strike) {
    const urls = [
      ...(Array.isArray(strike?.gcMatch?.source_urls) ? strike.gcMatch.source_urls : []),
      strike?.gcMatch?.source_url,
    ].filter(Boolean)

    for (const rawUrl of urls) {
      let parsed = null
      try {
        parsed = new URL(rawUrl)
      } catch {
        continue
      }

      const host = parsed.hostname.replace(/^www\./, "").toLowerCase()
      const pathname = parsed.pathname || ""

      const youtubeMatch = host === "youtu.be"
        ? pathname.slice(1)
        : (host.includes("youtube.com") ? parsed.searchParams.get("v") : null)
      if (youtubeMatch) {
        return {
          kind: "youtube",
          url: rawUrl,
          embedUrl: `https://www.youtube.com/embed/${encodeURIComponent(youtubeMatch)}?autoplay=1&mute=1&rel=0&modestbranding=1&origin=${encodeURIComponent(window.location.origin)}`,
        }
      }

      if (host === "x.com" || host === "twitter.com") {
        return { kind: "tweet", url: rawUrl }
      }

      if (/\.(mp4|webm|mov)(\?|$)/i.test(rawUrl)) {
        return { kind: "video", url: rawUrl }
      }
    }

    return null
  }

  // ── GeoConfirmed standalone detail ─────────────────────────
  GlobeController.prototype.showGeoconfirmedDetail = function(gc) {
    const date = gc.time ? new Date(gc.time) : null
    const ago = date ? this._timeAgo(date) : "Unknown"
    const timeStr = date ? date.toUTCString().replace("GMT", "UTC") : null

    // Build source links
    const srcUrls = gc.sourceUrls || []
    const geoUrls = gc.geoUrls || []
    const sourceCount = srcUrls.length

    const xUrl = srcUrls.find(u => u.includes("x.com/") || u.includes("twitter.com/"))
    const otherSrcUrls = srcUrls.filter(u => u !== xUrl)
    const primarySourceHtml = xUrl ? `
      <div style="margin:10px 0 6px;">
        <a href="${this._safeUrl(xUrl)}" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:7px;min-height:28px;padding:0 11px;border-radius:999px;border:1px solid rgba(255,152,0,0.22);background:rgba(255,152,0,0.09);font:600 9px var(--gt-mono);letter-spacing:0.7px;color:#ffbf6d;text-decoration:none;text-transform:uppercase;">
          <i class="fa-brands fa-x-twitter"></i> Open source on X
        </a>
      </div>
    ` : ""

    const sourcesHtml = otherSrcUrls.length > 0 ? `
      <div style="margin-top:8px;">
        <div style="font:600 9px var(--gt-mono);color:#ff9800;letter-spacing:1px;margin-bottom:4px;">SOURCES</div>
        ${otherSrcUrls.slice(0, 5).map(url => {
          const label = this._urlLabel(url)
          return `<a href="${this._safeUrl(url)}" target="_blank" rel="noopener" style="display:block;padding:3px 0;font:400 10px var(--gt-mono);color:rgba(200,210,225,0.6);text-decoration:none;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">
            <i class="${this._urlIcon(url)}" style="margin-right:5px;color:#ff9800;width:12px;text-align:center;"></i>${this._escapeHtml(label)}
          </a>`
        }).join("")}
      </div>
    ` : ""

    const geoHtml = geoUrls.length > 0 ? `
      <div style="margin-top:6px;">
        <div style="font:600 9px var(--gt-mono);color:rgba(200,210,225,0.25);letter-spacing:1px;margin-bottom:4px;">GEOLOCATION PROOF</div>
        ${geoUrls.slice(0, 3).map(url => {
          const label = this._urlLabel(url)
          return `<a href="${this._safeUrl(url)}" target="_blank" rel="noopener" style="display:block;padding:3px 0;font:400 10px var(--gt-mono);color:rgba(200,210,225,0.45);text-decoration:none;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">
            <i class="fa-solid fa-map-pin" style="margin-right:5px;color:rgba(200,210,225,0.3);width:12px;text-align:center;"></i>${this._escapeHtml(label)}
          </a>`
        }).join("")}
      </div>
    ` : ""

    // Find nearby FIRMS detections
    const nearbyFirms = (this._strikeDetections || []).filter(s =>
      Math.abs(s.lat - gc.lat) < 0.5 && Math.abs(s.lng - gc.lng) < 0.5
    ).slice(0, 3)

    const firmsHtml = nearbyFirms.length > 0 ? `
      <div style="margin-top:10px;padding:6px 8px;background:rgba(224,64,251,0.06);border:1px solid rgba(224,64,251,0.15);border-radius:4px;">
        <div style="font:600 9px var(--gt-mono);color:#e040fb;letter-spacing:0.5px;margin-bottom:4px;">SATELLITE HEAT SIGNATURES NEARBY</div>
        ${nearbyFirms.map(s => {
          const sTime = s.time ? this._timeAgo(new Date(s.time)) : ""
          return `<div style="font:400 10px var(--gt-mono);color:rgba(200,210,225,0.6);margin:2px 0;">
            ${s.frp ? s.frp.toFixed(0) + " MW" : "—"} · ${this._escapeHtml(s.satellite || "?")} · ${sTime}
          </div>`
        }).join("")}
      </div>
    ` : ""

    // Find nearby news
    const nearbyNews = (this._newsData || []).filter(n =>
      (n.category === "conflict" || n.category === "terror") &&
      Math.abs(n.lat - gc.lat) < 3.0 && Math.abs(n.lng - gc.lng) < 3.0
    ).slice(0, 3)

    const newsHtml = nearbyNews.length > 0 ? `
      <div style="margin-top:10px;padding-top:8px;border-top:1px solid rgba(255,255,255,0.08);">
        <div style="font:600 9px var(--gt-mono);color:#ff9800;letter-spacing:1px;margin-bottom:6px;">RELATED REPORTS</div>
        ${nearbyNews.map(n => {
          const nTime = n.time ? this._timeAgo(new Date(n.time)) : ""
          return `<a href="${this._safeUrl(n.url)}" target="_blank" rel="noopener" style="display:block;padding:5px 0;color:rgba(200,210,225,0.85);text-decoration:none;font-size:10px;line-height:1.3;border-bottom:1px solid rgba(255,255,255,0.04);">
            ${this._escapeHtml((n.title || "").length > 85 ? n.title.substring(0, 83) + "…" : (n.title || ""))}
            <div style="color:rgba(200,210,225,0.4);font-size:9px;margin-top:1px;">${this._escapeHtml(((n.publisher || n.source || "")).replace(/^GN:\s*/, ""))}${nTime ? " · " + nTime : ""}</div>
          </a>`
        }).join("")}
      </div>
    ` : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#ff9800;">
        <i class="fa-solid fa-location-dot" style="margin-right:6px;"></i>GeoConfirmed Report
      </div>
      <div style="margin:4px 0 6px;padding:4px 8px;background:rgba(255,152,0,0.08);border:1px solid rgba(255,152,0,0.2);border-radius:4px;font:500 9px var(--gt-mono);color:#ff9800;letter-spacing:0.5px;">
        VERIFIED GEOLOCATION · ${sourceCount} source${sourceCount !== 1 ? "s" : ""} · ${this._escapeHtml(gc.region || "")}
      </div>
      <div class="detail-country">${gc.lat.toFixed(4)}°, ${gc.lng.toFixed(4)}°</div>
      ${gc.description ? `<div style="margin:8px 0 4px;font:400 11px var(--gt-body);color:rgba(200,210,225,0.7);line-height:1.4;">${this._escapeHtml(gc.description.substring(0, 300))}</div>` : ""}
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Posted</span>
          <span class="detail-value">${ago}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Region</span>
          <span class="detail-value" style="color:#ff9800;">${this._escapeHtml(gc.region || "—")}</span>
        </div>
        ${timeStr ? `<div class="detail-field" style="grid-column:1/-1;">
          <span class="detail-label">Exact time</span>
          <span class="detail-value">${timeStr}</span>
        </div>` : ""}
      </div>
      ${primarySourceHtml}
      ${sourcesHtml}
      ${geoHtml}
      ${firmsHtml}
      ${newsHtml}
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: GeoConfirmed.org — community-verified geolocation</div>
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""

    this._fetchConnections("geoconfirmed_event", gc.lat, gc.lng)
  }

  GlobeController.prototype.expandGeoconfirmedDetail = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()

    // Find the gc data from the active or pinned anchored state
    const anchorId = event?.currentTarget?.dataset?.anchorId
    let state = null
    if (anchorId === "active" || !anchorId) {
      state = this._anchoredDetailState
    } else {
      state = (this._pinnedAnchoredDetails || []).find(s => s.anchorId === anchorId)
    }

    const gc = state?._gcData
    if (!gc) return

    this.showGeoconfirmedDetail(gc)
  }

  GlobeController.prototype._loadXEmbed = async function(url, containerId) {
    const container = document.getElementById(containerId || "gc-embed-container")
    if (!container) return
    this._renderXEmbedFallback?.(url, container)
  }

  GlobeController.prototype._renderXEmbedFallback = function(url, container) {
    if (!container) return
    container.innerHTML = `<a href="${this._safeUrl(url)}" target="_blank" rel="noopener" style="font:400 10px var(--gt-mono);color:#ff9800;text-decoration:none;"><i class="fa-brands fa-x-twitter" style="margin-right:5px;"></i>View post on X</a>`
  }

  // ── URL helpers ────────────────────────────────────────────
  GlobeController.prototype._urlLabel = function(url) {
    try {
      const u = new URL(url)
      const host = u.hostname.replace(/^www\./, "")
      if (host === "x.com" || host === "twitter.com") {
        const m = u.pathname.match(/^\/([^/]+)/)
        return m ? `@${m[1]}` : host
      }
      if (host === "t.me") {
        const m = u.pathname.match(/^\/([^/]+)/)
        return m ? `t.me/${m[1]}` : host
      }
      if (host.includes("facebook.com")) return "Facebook"
      if (host.includes("bsky.app")) return "Bluesky"
      if (host.includes("youtube.com") || host === "youtu.be") return "YouTube"
      if (host.includes("warspotting.net")) return "Warspotting"
      if (host.includes("maps.app.goo.gl") || host.includes("google.com")) return "Google Maps"
      if (host.includes("wikimapia")) return "Wikimapia"
      return host
    } catch { return url.substring(0, 40) }
  }

  GlobeController.prototype._urlIcon = function(url) {
    try {
      const host = new URL(url).hostname
      if (host === "x.com" || host === "twitter.com") return "fa-brands fa-x-twitter"
      if (host === "t.me") return "fa-brands fa-telegram"
      if (host.includes("facebook.com")) return "fa-brands fa-facebook"
      if (host.includes("bsky.app")) return "fa-brands fa-bluesky"
      if (host.includes("youtube.com") || host === "youtu.be") return "fa-brands fa-youtube"
      return "fa-solid fa-arrow-up-right-from-square"
    } catch { return "fa-solid fa-link" }
  }
}
