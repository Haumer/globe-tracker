import { getDataSource } from "globe/utils"
import {
  renderCameraListCard,
  renderFeaturedCameraCard,
  renderWebcamDetailHtml,
} from "globe/controller/situational_presenters"

export function applySituationalCameraMethods(GlobeController) {
  GlobeController.prototype.getWebcamsDataSource = function() {
    const dataSource = getDataSource(this.viewer, this._ds, "webcams")
    dataSource.show = this.camerasVisible
    return dataSource
  }

  GlobeController.prototype._extractWindyUrl = function(field, prop = "link") {
    if (!field) return null
    if (typeof field === "string" && field.startsWith("http")) return field
    if (typeof field === "object") {
      const val = field[prop]
      if (typeof val === "string" && val.startsWith("http")) return val
      const other = prop === "link" ? "embed" : "link"
      const val2 = field[other]
      if (typeof val2 === "string" && val2.startsWith("http")) return val2
    }
    return null
  }

  GlobeController.prototype.toggleCameras = function() {
    this.camerasVisible = this.hasCamerasToggleTarget && this.camerasToggleTarget.checked
    if (this.camerasVisible) {
      this.getWebcamsDataSource().show = true
      this.fetchWebcams()
      this._showRightPanel("cameras")
      if (!this._webcamMoveHandler) {
        this._webcamMoveHandler = () => {
          if (this.camerasVisible) this._maybeRefetchWebcams()
        }
        this.viewer.camera.moveEnd.addEventListener(this._webcamMoveHandler)
      }
    } else {
      this._webcamFetchToken += 1
      this._clearWebcamEntities()
      this._webcamData = []
      const dataSource = this._ds["webcams"]
      if (dataSource) dataSource.show = false
      if (this._syncRightPanels) this._syncRightPanels()
    }
    this._updateStats()
    this._requestRender()
    this._savePrefs()
  }

  GlobeController.prototype._maybeRefetchWebcams = function() {
    const center = this._getViewCenter()
    if (!center) return
    if (this._webcamLastFetchCenter) {
      const dLat = Math.abs(center.lat - this._webcamLastFetchCenter.lat)
      const dLng = Math.abs(center.lng - this._webcamLastFetchCenter.lng)
      const dHeight = Math.abs(center.height - (this._webcamLastFetchCenter.height || 0))
      if (dLat < 0.5 && dLng < 0.5 && dHeight < center.height * 0.3) return
    }
    this.fetchWebcams()
  }

  GlobeController.prototype._getViewCenter = function() {
    const Cesium = window.Cesium
    if (!this.viewer) return null

    const canvas = this.viewer.scene.canvas
    const center = new Cesium.Cartesian2(canvas.clientWidth / 2, canvas.clientHeight / 2)
    const ray = this.viewer.camera.getPickRay(center)
    const intersection = ray ? this.viewer.scene.globe.pick(ray, this.viewer.scene) : null

    if (intersection) {
      const carto = Cesium.Cartographic.fromCartesian(intersection)
      return {
        lat: Cesium.Math.toDegrees(carto.latitude),
        lng: Cesium.Math.toDegrees(carto.longitude),
        height: this.viewer.camera.positionCartographic.height,
      }
    }

    const carto = this.viewer.camera.positionCartographic
    return {
      lat: Cesium.Math.toDegrees(carto.latitude),
      lng: Cesium.Math.toDegrees(carto.longitude),
      height: carto.height,
    }
  }

  GlobeController.prototype._getViewportBbox = function() {
    const Cesium = window.Cesium
    if (!this.viewer) return null
    const canvas = this.viewer.scene.canvas
    const corners = [
      new Cesium.Cartesian2(0, 0),
      new Cesium.Cartesian2(canvas.clientWidth, 0),
      new Cesium.Cartesian2(canvas.clientWidth, canvas.clientHeight),
      new Cesium.Cartesian2(0, canvas.clientHeight),
    ]
    let minLat = 90, maxLat = -90, minLng = 180, maxLng = -180
    let hits = 0

    if (this.viewer.scene.globe.show) {
      for (const corner of corners) {
        const ray = this.viewer.camera.getPickRay(corner)
        const pos = ray ? this.viewer.scene.globe.pick(ray, this.viewer.scene) : null
        if (pos) {
          const carto = Cesium.Cartographic.fromCartesian(pos)
          const lat = Cesium.Math.toDegrees(carto.latitude)
          const lng = Cesium.Math.toDegrees(carto.longitude)
          minLat = Math.min(minLat, lat)
          maxLat = Math.max(maxLat, lat)
          minLng = Math.min(minLng, lng)
          maxLng = Math.max(maxLng, lng)
          hits++
        }
      }
    }

    if (hits < 2) {
      const carto = this.viewer.camera.positionCartographic
      const lat = Cesium.Math.toDegrees(carto.latitude)
      const lng = Cesium.Math.toDegrees(carto.longitude)
      const heightKm = carto.height / 1000
      const spanDeg = Math.min(Math.max(heightKm / 111, 0.1), 30)
      return {
        north: lat + spanDeg,
        south: lat - spanDeg,
        east: lng + spanDeg / Math.max(Math.cos(lat * Math.PI / 180), 0.01),
        west: lng - spanDeg / Math.max(Math.cos(lat * Math.PI / 180), 0.01),
      }
    }

    return { north: maxLat, south: minLat, east: maxLng, west: minLng }
  }

  GlobeController.prototype._buildWebcamFetchPlan = function(center) {
    const viewport = this._getViewportBbox()
    const filterBounds = this.hasActiveFilter() ? this.getFilterBounds() : null

    let north, south, east, west
    if (viewport) {
      north = viewport.north
      south = viewport.south
      east = viewport.east
      west = viewport.west
    } else {
      const spanDeg = Math.min(Math.max(center.height / 111000, 0.5), 30)
      north = center.lat + spanDeg
      south = center.lat - spanDeg
      east = center.lng + spanDeg
      west = center.lng - spanDeg
    }

    if (filterBounds) {
      north = Math.min(north, filterBounds.lamax + 0.15)
      south = Math.max(south, filterBounds.lamin - 0.15)
      east = Math.min(east, filterBounds.lomax + 0.15)
      west = Math.max(west, filterBounds.lomin - 0.15)
    }

    const latPad = Math.max((north - south) * 0.15, 0.25)
    const lngPad = Math.max((east - west) * 0.15, 0.25)

    return {
      query: [
        `north=${Math.min(north + latPad, 85).toFixed(4)}`,
        `south=${Math.max(south - latPad, -85).toFixed(4)}`,
        `east=${Math.min(east + lngPad, 180).toFixed(4)}`,
        `west=${Math.max(west - lngPad, -180).toFixed(4)}`,
      ].join("&"),
      limit: center.height > 1500000 ? 150 : 100,
    }
  }

  GlobeController.prototype.fetchWebcams = async function() {
    if (!this.camerasVisible) return
    const center = this._getViewCenter()
    if (!center) return
    const fetchId = ++this._webcamFetchToken
    const plan = this._buildWebcamFetchPlan(center)
    const url = `/api/webcams?${plan.query}&limit=${plan.limit}`

    this._toast("Loading cameras...")

    try {
      const resp = await fetch(url)
      if (fetchId !== this._webcamFetchToken) return
      if (resp.ok) {
        const data = await resp.json()
        if (fetchId !== this._webcamFetchToken) return
        const cams = data.webcams || []
        this._webcamCollectionStatus = data.stale ? "stale" : "ready"

        this._webcamData = cams.map(w => this._normalizeWebcam(w)).filter(w =>
          w.lat != null && w.lng != null && Number.isFinite(w.lat) && Number.isFinite(w.lng)
        )
        this.renderWebcams()
        this._updateStats()
        if (this._syncRightPanels) this._syncRightPanels()
      }
    } catch (e) {
      console.warn("Webcam fetch failed:", e)
    }

    if (fetchId === this._webcamFetchToken) {
      this._webcamLastFetchCenter = center
      if (this._syncRightPanels) this._syncRightPanels()
      this._toastHide()
    }
  }

  GlobeController.prototype._normalizeWebcam = function(w) {
    return {
      id: w.webcamId || w.id,
      title: w.title,
      source: w.source || "windy",
      live: w.live || false,
      realtime: w.realtime || false,
      mode: w.mode || null,
      cameraType: w.cameraType || null,
      lat: w.location?.latitude,
      lng: w.location?.longitude,
      city: w.location?.city,
      region: w.location?.region,
      country: w.location?.country,
      thumbnail: w.images?.current?.preview || w.images?.daylight?.preview,
      thumbnailIcon: w.images?.current?.icon || w.images?.daylight?.icon,
      playerLink: this._extractWindyUrl(w.player?.live) || this._extractWindyUrl(w.player?.day) || (typeof w.url === "string" ? w.url : null),
      videoId: w.videoId || null,
      channelTitle: w.channelTitle || null,
      lastUpdated: w.lastUpdatedOn,
      freshnessSeconds: Number.isFinite(w.freshnessSeconds) ? w.freshnessSeconds : null,
      viewCount: w.viewCount,
      stale: !!w.stale,
    }
  }

  GlobeController.prototype._cameraMode = function(cam) {
    if (!cam) return "periodic"
    if (cam.mode) return cam.mode
    if (cam.stale) return "stale"
    if (cam.realtime || cam.source === "youtube" || cam.source === "nycdot") return "realtime"
    if (cam.live) return "live"
    return "periodic"
  }

  GlobeController.prototype._cameraFreshnessSeconds = function(cam) {
    if (Number.isFinite(cam?.freshnessSeconds)) return cam.freshnessSeconds
    if (!cam?.lastUpdated) return null

    const updatedAt = new Date(cam.lastUpdated).getTime()
    if (Number.isNaN(updatedAt)) return null

    return Math.max(0, Math.round((Date.now() - updatedAt) / 1000))
  }

  GlobeController.prototype._cameraFreshnessLabel = function(cam) {
    if (cam?.stale) return "stale cache"

    const seconds = this._cameraFreshnessSeconds(cam)
    if (seconds == null) {
      return this._cameraMode(cam) === "realtime" ? "live now" : "recent"
    }

    if (seconds < 60) return "updated just now"
    if (seconds < 3600) return `updated ${Math.round(seconds / 60)}m ago`
    if (seconds < 86_400) return `updated ${Math.round(seconds / 3600)}h ago`
    return `updated ${Math.round(seconds / 86_400)}d ago`
  }

  GlobeController.prototype._cameraSourceLabel = function(cam) {
    return { windy: "Windy", nycdot: "NYC DOT", youtube: "YouTube" }[cam?.source] || (cam?.source || "Camera")
  }

  GlobeController.prototype._cameraModeBadge = function(cam) {
    const mode = this._cameraMode(cam)
    return {
      realtime: { label: "LIVE NOW", tone: "realtime" },
      live: { label: "ACTIVE", tone: "live" },
      periodic: { label: "PERIODIC", tone: "periodic" },
      stale: { label: "STALE", tone: "stale" },
    }[mode]
  }

  GlobeController.prototype._cameraModeChipClass = function(cam) {
    return {
      realtime: "fire",
      live: "event",
      periodic: "eq",
      stale: "outage",
    }[this._cameraMode(cam)] || "eq"
  }

  GlobeController.prototype._cameraSourceColor = function(cam) {
    return { youtube: "#ff5252", nycdot: "#ff6d00", windy: "#29b6f6" }[cam?.source] || "#29b6f6"
  }

  GlobeController.prototype._cameraPriorityScore = function(cam) {
    const mode = this._cameraMode(cam)
    const base = { realtime: 4000, live: 3000, periodic: 2000, stale: 1000 }[mode] || 1500
    const freshness = this._cameraFreshnessSeconds(cam)
    const freshnessBoost = freshness == null ? 0 : Math.max(0, 900 - freshness / 60)
    const audienceBoost = cam?.viewCount ? Math.min(250, Math.log10(cam.viewCount + 1) * 60) : 0
    const visualBoost = cam?.thumbnail ? 35 : 0
    return base + freshnessBoost + audienceBoost + visualBoost
  }

  GlobeController.prototype._sortWebcams = function(cams) {
    return [...cams].sort((a, b) => {
      const scoreDelta = this._cameraPriorityScore(b) - this._cameraPriorityScore(a)
      if (scoreDelta !== 0) return scoreDelta

      const freshnessDelta = (this._cameraFreshnessSeconds(a) ?? Number.POSITIVE_INFINITY) -
        (this._cameraFreshnessSeconds(b) ?? Number.POSITIVE_INFINITY)
      if (freshnessDelta !== 0) return freshnessDelta

      return (a.title || "").localeCompare(b.title || "")
    })
  }

  GlobeController.prototype._cameraThumbUrl = function(cam, options = {}) {
    const raw = cam?.thumbnail
    if (!(typeof raw === "string") || !/^https?:\/\//i.test(raw)) return null

    const shouldBustCache = options.cacheBust || cam?.source === "nycdot"
    if (!shouldBustCache) return raw

    return `${raw}${raw.includes("?") ? "&" : "?"}t=${Date.now()}`
  }

  GlobeController.prototype._cameraWatchUrl = function(cam) {
    const rawWatchUrl = cam?.source === "youtube" && cam?.videoId
      ? `https://www.youtube.com/watch?v=${encodeURIComponent(cam.videoId)}`
      : cam?.source === "nycdot"
        ? "https://webcams.nyctmc.org/map"
        : (typeof cam?.playerLink === "string" && /^https:\/\//i.test(cam.playerLink)
            ? cam.playerLink
            : `https://www.windy.com/webcams/${encodeURIComponent(cam?.id || "")}`)

    return this._safeUrl(rawWatchUrl)
  }

  GlobeController.prototype.renderWebcams = function() {
    const Cesium = window.Cesium
    this._clearWebcamEntities()
    const dataSource = this.getWebcamsDataSource()
    dataSource.show = this.camerasVisible
    if (!this.camerasVisible) {
      this._requestRender()
      return
    }
    this._webcamEntityMap.clear()
    const visibleCams = this._sortWebcams(
      this._webcamData.filter(w => !this.hasActiveFilter() || this.pointPassesFilter(w.lat, w.lng))
    )
    const highlightedLabels = new Set(
      visibleCams
        .filter(cam => {
          const mode = this._cameraMode(cam)
          return mode === "realtime" || mode === "live"
        })
        .slice(0, 16)
        .map(cam => cam.id)
    )

    const CAM_HEIGHT_OFFSET = 25

    dataSource.entities.suspendEvents()
    visibleCams.forEach(w => {
      const mode = this._cameraMode(w)
      const icon = mode === "realtime"
        ? (this._webcamIconRT || (this._webcamIconRT = this._makeWebcamIcon("#ff4444", { mode: "realtime" })))
        : mode === "live"
          ? (this._webcamIconLive || (this._webcamIconLive = this._makeWebcamIcon("#4caf50", { mode: "live" })))
          : mode === "stale"
            ? (this._webcamIconStale || (this._webcamIconStale = this._makeWebcamIcon("#7f8a99", { mode: "stale" })))
            : (this._webcamIcon || (this._webcamIcon = this._makeWebcamIcon("#29b6f6", { mode: "periodic" })))
      const labelPrefix = mode === "realtime" ? "LIVE · " : mode === "live" ? "OBS · " : ""
      const showLabel = highlightedLabels.has(w.id) || visibleCams.length <= 18
      const baseScale = mode === "realtime" ? 0.84 : mode === "live" ? 0.76 : mode === "stale" ? 0.62 : 0.68
      const entity = dataSource.entities.add({
        id: `cam-${w.id}`,
        position: Cesium.Cartesian3.fromDegrees(w.lng, w.lat, CAM_HEIGHT_OFFSET),
        properties: {
          webcamId: w.id,
        },
        billboard: {
          image: icon,
          scale: baseScale,
          scaleByDistance: new Cesium.NearFarScalar(500, 1.2, 5e6, 0.4),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          heightReference: Cesium.HeightReference.NONE,
        },
        label: {
          text: showLabel ? labelPrefix + (w.title.length > 25 ? w.title.substring(0, 23) + "…" : w.title) : "",
          font: "12px JetBrains Mono, sans-serif",
          fillColor: Cesium.Color.WHITE.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.6),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(500, 1, 3e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(500, 1, 1.5e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          heightReference: Cesium.HeightReference.NONE,
        },
      })
      this._webcamEntities.push(entity)
      this._webcamEntityMap.set(entity.id, w)
    })
    dataSource.entities.resumeEvents()

    this._requestRender()
    this._renderCamFeed()

    if (visibleCams.length > 0 && this.viewer.scene.sampleHeightMostDetailed) {
      const cartographics = visibleCams.map(w =>
        Cesium.Cartographic.fromDegrees(w.lng, w.lat)
      )
      this.viewer.scene.sampleHeightMostDetailed(cartographics).then(updated => {
        updated.forEach((carto, i) => {
          const entity = this._webcamEntities[i]
          if (!entity) return
          const groundHeight = carto.height || 0
          entity.position = Cesium.Cartesian3.fromDegrees(
            Cesium.Math.toDegrees(carto.longitude),
            Cesium.Math.toDegrees(carto.latitude),
            groundHeight + CAM_HEIGHT_OFFSET
          )
        })
        this._requestRender()
      }).catch(() => {})
    }
  }

  GlobeController.prototype._renderCamFeed = function() {
    if (!this.hasCamFeedListTarget) return
    const search = this.hasCamFeedSearchTarget ? this.camFeedSearchTarget.value.toLowerCase().trim() : ""
    const cams = this._sortWebcams(this._webcamData.filter(w => {
      if (search && !(w.title || "").toLowerCase().includes(search) &&
          !(w.city || "").toLowerCase().includes(search) &&
          !(w.country || "").toLowerCase().includes(search)) return false
      return true
    }))

    const counts = cams.reduce((memo, cam) => {
      memo[this._cameraMode(cam)] += 1
      return memo
    }, { realtime: 0, live: 0, periodic: 0, stale: 0 })

    if (this.hasCamFeedCountTarget) {
      const base = `${cams.length} camera${cams.length !== 1 ? "s" : ""}`
      const activeFeeds = counts.realtime + counts.live
      const suffixParts = []
      if (activeFeeds > 0) suffixParts.push(`${activeFeeds} active`)
      if (counts.stale > 0) suffixParts.push(`${counts.stale} stale`)
      if (this._webcamCollectionStatus === "stale") suffixParts.push("stale cache")
      const suffix = suffixParts.length ? ` · ${suffixParts.join(" · ")}` : ""
      this.camFeedCountTarget.textContent = `${base}${suffix}`
    }

    if (cams.length === 0) {
      const emptyLabel = this._webcamCollectionStatus === "stale" ? "No cameras in the current cached view." : "No cameras found"
      this.camFeedListTarget.innerHTML = `<div style="padding:24px 14px;text-align:center;color:var(--gt-text-dim);font:500 11px var(--gt-mono);">${emptyLabel}</div>`
      return
    }

    const featured = cams.filter(cam => {
      const mode = this._cameraMode(cam)
      return mode === "realtime" || mode === "live"
    }).slice(0, 3)
    const featuredIds = new Set(featured.map(cam => cam.id))
    const remaining = cams.filter(cam => !featuredIds.has(cam.id))

    const summaryHtml = `
      <div class="cam-feed-summary insight-card-chips">
        <span class="ins-chip ins-chip--fire">${counts.realtime} live now</span>
        <span class="ins-chip ins-chip--event">${counts.live} active feeds</span>
        <span class="ins-chip ins-chip--eq">${counts.periodic} periodic</span>
        ${counts.stale > 0 ? `<span class="ins-chip ins-chip--outage">${counts.stale} stale</span>` : ""}
      </div>
    `

    const featuredHtml = featured.length ? `
      <div class="cam-live-section">
        <div class="cam-live-header">Live Observation</div>
        <div class="cam-live-grid">
          ${featured.map(cam => this._renderFeaturedCameraCard(cam)).join("")}
        </div>
      </div>
    ` : ""

    const listHtml = remaining.length ? `
      <div class="cam-list-section">
        <div class="cam-list-header">All Cameras In View</div>
        ${remaining.map(cam => this._renderCameraListCard(cam)).join("")}
      </div>
    ` : ""

    this.camFeedListTarget.innerHTML = summaryHtml + featuredHtml + listHtml
  }

  GlobeController.prototype._renderFeaturedCameraCard = function(cam) {
    return renderFeaturedCameraCard(this, cam, this._webcamData.indexOf(cam))
  }

  GlobeController.prototype._renderCameraListCard = function(cam) {
    return renderCameraListCard(this, cam, this._webcamData.indexOf(cam))
  }

  GlobeController.prototype.filterCamFeed = function() {
    this._renderCamFeed()
  }

  GlobeController.prototype.closeCamFeed = function() {
    if (this._syncRightPanels) this._syncRightPanels()
  }

  GlobeController.prototype._clearWebcamEntities = function() {
    const ds = this._ds["webcams"]
    if (ds) {
      ds.entities.suspendEvents()
      this._webcamEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._webcamEntities = []
    this._webcamEntityMap.clear()
    this._requestRender()
  }

  GlobeController.prototype.showWebcamDetail = function(cam) {
    if (this._webcamRefreshInterval) {
      clearInterval(this._webcamRefreshInterval)
      this._webcamRefreshInterval = null
    }
    if (this._ytMessageCleanup) {
      this._ytMessageCleanup()
      this._ytMessageCleanup = null
    }

    const updated = cam.lastUpdated ? this._timeAgo(new Date(cam.lastUpdated)) : "—"
    const location = [cam.city, cam.region, cam.country].filter(Boolean).join(", ")
    const sourceLabel = this._cameraSourceLabel(cam)
    const modeBadge = this._cameraModeBadge(cam)
    const freshnessLabel = this._cameraFreshnessLabel(cam)
    const cacheMeta = this._cacheMeta(cam.lastUpdated, cam.stale ? cam.lastUpdated : null)
    const liveBadge = `<span style="background:${modeBadge.tone === "realtime" ? "#ff4444" : modeBadge.tone === "live" ? "#4caf50" : modeBadge.tone === "stale" ? "#ffb300" : "#666"};color:${modeBadge.tone === "stale" ? "#111" : "#fff"};font:700 8px var(--gt-mono);padding:1px 5px;border-radius:2px;letter-spacing:1px;margin-left:6px;">${modeBadge.label}</span>`

    const thumbUrl = this._cameraThumbUrl(cam, { cacheBust: true })
    const watchUrl = this._cameraWatchUrl(cam)

    let thumbHtml
    if (cam.source === "youtube" && cam.videoId) {
      const safeVideoId = encodeURIComponent(cam.videoId)
      const ytThumb = (cam.thumbnail && /^https?:\/\//i.test(cam.thumbnail)) ? cam.thumbnail : `https://img.youtube.com/vi/${safeVideoId}/hqdefault.jpg`
      thumbHtml = `<div class="webcam-thumb" style="position:relative;">
        <iframe id="webcam-detail-iframe" src="https://www.youtube.com/embed/${safeVideoId}?autoplay=1&mute=1&enablejsapi=1&origin=${encodeURIComponent(window.location.origin)}" style="width:100%;aspect-ratio:16/9;border:none;border-radius:4px;" allow="autoplay; encrypted-media" allowfullscreen></iframe>
        <div id="webcam-yt-fallback" style="display:none;position:relative;">
          <img src="${ytThumb}" alt="${this._escapeHtml(cam.title)}" style="width:100%;border-radius:4px;">
          <span style="position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,0.7);color:#ff6b6b;font:500 11px var(--gt-mono);padding:6px 12px;border-radius:4px;">Stream unavailable</span>
        </div>
      </div>`
      const showFallback = () => {
        const iframe = document.getElementById("webcam-detail-iframe")
        const fallback = document.getElementById("webcam-yt-fallback")
        if (iframe) iframe.style.display = "none"
        if (fallback) fallback.style.display = "block"
      }
      const onYtMessage = (e) => {
        if (typeof e.data !== "string") return
        try {
          const msg = JSON.parse(e.data)
          if (msg.event === "onError") {
            showFallback()
            window.removeEventListener("message", onYtMessage)
          }
        } catch {}
      }
      window.addEventListener("message", onYtMessage)
      setTimeout(() => {
        const iframe = document.getElementById("webcam-detail-iframe")
        if (iframe?.contentWindow) {
          iframe.contentWindow.postMessage(JSON.stringify({ event: "listening", id: 1 }), "https://www.youtube.com")
        }
      }, 1500)
      this._ytMessageCleanup = () => window.removeEventListener("message", onYtMessage)
    } else if (thumbUrl) {
      thumbHtml = `<div class="webcam-thumb" style="position:relative;">
        <img id="webcam-detail-img" src="${thumbUrl}" alt="${this._escapeHtml(cam.title)}" style="width:100%;border-radius:4px;transition:opacity 0.3s;">
        <span style="position:absolute;top:6px;left:6px;background:rgba(0,0,0,0.6);color:#ff4444;font:700 9px var(--gt-mono);padding:2px 6px;border-radius:3px;letter-spacing:0.5px;">● LIVE</span>
      </div>`
    } else {
      thumbHtml = ""
    }

    this.detailContentTarget.innerHTML = renderWebcamDetailHtml(this, cam, thumbHtml, watchUrl, {
      cacheMeta,
      freshnessLabel,
      liveBadge,
      location,
      modeBadge,
      sourceLabel,
      updated,
    })
    this.detailPanelTarget.style.display = ""

    const refreshable = (cam.source === "nycdot" || cam.source === "windy") && cam.thumbnail
    if (refreshable) {
      const interval = cam.source === "nycdot" ? 5000 : 15000
      this._webcamRefreshInterval = setInterval(() => {
        const img = document.getElementById("webcam-detail-img")
        if (img) img.src = `${cam.thumbnail}?t=${Date.now()}`
      }, interval)
    }

    if (this.viewer?.camera && Number.isFinite(cam.lng) && Number.isFinite(cam.lat)) {
      try {
        const Cesium = window.Cesium
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(cam.lng, cam.lat, 50000),
          duration: 1.5,
        })
      } catch (error) {
        console.warn("Webcam fly-to failed:", error)
      }
    }
  }
}
