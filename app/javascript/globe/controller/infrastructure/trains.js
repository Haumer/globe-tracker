import { getDataSource, createTrainIcon, LABEL_DEFAULTS } from "../../utils"

const TRAIN_COLORS = {
  // High-speed / long distance
  ICE: "#e53935", RJ: "#e53935", RJX: "#e53935", TGV: "#e53935", Thalys: "#e53935",
  IC: "#ff9800", EC: "#ff9800", EN: "#ff9800", NJ: "#ff9800", D: "#ff9800",
  // Regional
  RE: "#66bb6a", REX: "#66bb6a", R: "#66bb6a", RB: "#66bb6a", IR: "#66bb6a",
  TER: "#66bb6a", IRE: "#66bb6a",
  // Suburban
  S: "#42a5f5",
  // Other
  WB: "#26c6da",
}

function trainColor(category) {
  return TRAIN_COLORS[category] || "#90a4ae"
}

const DEFAULT_LERP_DURATION = 10000 // ms — fallback for first movement
const LATENCY_BUFFER = 1.2 // run 20% slower to absorb network jitter

export function applyTrainsMethods(GlobeController) {
  GlobeController.prototype.getTrainsDataSource = function() {
    return getDataSource(this.viewer, this._ds, "trains")
  }

  GlobeController.prototype.toggleTrains = function() {
    this.trainsVisible = this.hasTrainsToggleTarget && this.trainsToggleTarget.checked
    if (this.trainsVisible) {
      if (!this._trainPositions) this._trainPositions = new Map()
      this.fetchTrains()
      if (!this._trainPollTimer) {
        this._trainPollTimer = setInterval(() => {
          if (this.trainsVisible) this.fetchTrains()
        }, 10000)
      }
    } else {
      this._clearTrainEntities()
      if (this._trainPollTimer) {
        clearInterval(this._trainPollTimer)
        this._trainPollTimer = null
      }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchTrains = async function() {
    if (this._trainFetching) return
    this._trainFetching = true

    let url = "/api/trains"
    const bounds = this.getViewportBounds() || this.getFilterBounds()
    if (bounds) {
      url += `?bbox=${bounds.lamin},${bounds.lomin},${bounds.lamax},${bounds.lomax}`
    }

    try {
      const resp = await fetch(url)
      if (!resp.ok) return
      const newData = await resp.json()
      this._trainData = newData
      this._updateTrainPositions(newData)
      this.renderTrains()
    } catch (e) {
      console.error("Failed to fetch trains:", e)
    } finally {
      this._trainFetching = false
    }
  }

  // Store previous + target positions for interpolation
  GlobeController.prototype._updateTrainPositions = function(trains) {
    if (!this._trainPositions) this._trainPositions = new Map()
    const now = performance.now()
    const seen = new Set()

    for (const t of trains) {
      if (!t.lat || !t.lng) continue
      seen.add(t.id)
      const prev = this._trainPositions.get(t.id)

      if (prev) {
        // Train existed before — set up animation from current rendered pos to new pos
        const hasMoved = Math.abs(prev.targetLat - t.lat) > 0.00001 ||
                         Math.abs(prev.targetLng - t.lng) > 0.00001
        prev.fromLat = prev.currentLat
        prev.fromLng = prev.currentLng
        prev.targetLat = t.lat
        prev.targetLng = t.lng
        if (hasMoved) {
          // Measure actual time between position changes for lerp duration
          const dt = prev.lastMovedAt ? (now - prev.lastMovedAt) : DEFAULT_LERP_DURATION
          prev.lerpDuration = dt * LATENCY_BUFFER
          // Estimate speed: haversine distance / time
          const dLat = t.lat - prev.targetLat
          const dLng = t.lng - prev.targetLng
          const distKm = Math.sqrt(dLat * dLat + dLng * dLng * Math.cos(t.lat * Math.PI / 180) ** 2) * 111.32
          prev.speedKmh = Math.round(distKm / (dt / 3600000))
          prev.lastMovedAt = now
        }
        prev.startTime = now
        // Only mark stopped after 30s of no position change
        prev.moving = (now - (prev.lastMovedAt || 0)) < 30000
      } else {
        // New train — assume moving until proven otherwise
        this._trainPositions.set(t.id, {
          fromLat: t.lat, fromLng: t.lng,
          targetLat: t.lat, targetLng: t.lng,
          currentLat: t.lat, currentLng: t.lng,
          startTime: now,
          lastMovedAt: now,
          lerpDuration: DEFAULT_LERP_DURATION,
          moving: true,
        })
      }
    }

    // Remove trains that disappeared
    for (const id of this._trainPositions.keys()) {
      if (!seen.has(id)) this._trainPositions.delete(id)
    }
  }

  GlobeController.prototype.renderTrains = function() {
    if (!this._trainData || !this.trainsVisible) {
      this._clearTrainEntities()
      return
    }

    const Cesium = window.Cesium
    const dataSource = this.getTrainsDataSource()
    const iconCache = {}
    const existingMap = new Map()

    // Index existing entities by train id
    for (const e of this._trainEntities) {
      const id = e.id?.replace("train-", "")
      if (id) existingMap.set(id, e)
    }

    const newEntities = []
    const activeIds = new Set()

    dataSource.entities.suspendEvents()
    this._trainData.forEach(t => {
      if (!t.lat || !t.lng) return
      activeIds.add(t.id)

      const color = trainColor(t.category)
      if (!iconCache[color]) iconCache[color] = createTrainIcon(color)

      const pos = this._trainPositions?.get(t.id)
      const lat = pos ? pos.currentLat : t.lat
      const lng = pos ? pos.currentLng : t.lng

      const existing = existingMap.get(t.id)
      if (existing) {
        // Update position — don't recreate entity
        existing.position = Cesium.Cartesian3.fromDegrees(lng, lat, 50)
        newEntities.push(existing)
        existingMap.delete(t.id)
      } else {
        // Create new entity
        const entity = dataSource.entities.add({
          id: `train-${t.id}`,
          position: Cesium.Cartesian3.fromDegrees(lng, lat, 50),
          billboard: {
            image: iconCache[color],
            scale: 1,
            heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            scaleByDistance: new Cesium.NearFarScalar(5e4, 1, 5e6, 0.4),
          },
          label: {
            text: t.name || "",
            font: LABEL_DEFAULTS.font,
            outlineWidth: LABEL_DEFAULTS.outlineWidth,
            style: LABEL_DEFAULTS.style(),
            outlineColor: LABEL_DEFAULTS.outlineColor(),
            fillColor: Cesium.Color.fromCssColorString(color),
            scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
            translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
            pixelOffset: LABEL_DEFAULTS.pixelOffsetBelow(),
            disableDepthTestDistance: LABEL_DEFAULTS.disableDepthTest,
          },
          properties: {
            type: "train",
            trainData: t,
          },
        })
        newEntities.push(entity)
      }
    })

    // Remove entities for trains that are gone
    for (const [, entity] of existingMap) {
      dataSource.entities.remove(entity)
    }

    this._trainEntities = newEntities
    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  // Called from the main animation loop — interpolates train positions
  GlobeController.prototype._animateTrains = function(now) {
    if (!this.trainsVisible || !this._trainPositions?.size) return false

    const Cesium = window.Cesium
    let needsRender = false

    for (const [id, pos] of this._trainPositions) {
      const elapsed = now - pos.startTime
      const duration = pos.lerpDuration || DEFAULT_LERP_DURATION
      const t = Math.min(elapsed / duration, 1)

      const newLat = pos.fromLat + (pos.targetLat - pos.fromLat) * t
      const newLng = pos.fromLng + (pos.targetLng - pos.fromLng) * t

      if (Math.abs(newLat - pos.currentLat) > 0.000001 || Math.abs(newLng - pos.currentLng) > 0.000001) {
        pos.currentLat = newLat
        pos.currentLng = newLng

        // Find and update the entity
        const entity = this._trainEntities.find(e => e.id === `train-${id}`)
        if (entity) {
          entity.position = Cesium.Cartesian3.fromDegrees(newLng, newLat, 50)
          needsRender = true
        }
      }

      // After animation completes, snap to target
      if (t >= 1) {
        pos.currentLat = pos.targetLat
        pos.currentLng = pos.targetLng
      }
    }

    // Follow tracked train
    if (this.trackedTrainId) {
      const pos = this._trainPositions.get(this.trackedTrainId)
      if (pos) {
        const h = this._trackingHeights[this._trackingHeightIdx]
        this.viewer.camera.setView({
          destination: Cesium.Cartesian3.fromDegrees(pos.currentLng, pos.currentLat, h),
        })
        needsRender = true
      }
    }

    return needsRender
  }

  GlobeController.prototype._clearTrainEntities = function() {
    const ds = this._ds["trains"]
    if (ds) {
      ds.entities.suspendEvents()
      this._trainEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._trainEntities = []
  }

  GlobeController.prototype.showTrainDetail = function(train) {
    if (!this.hasDetailPanelTarget) return
    const t = train
    const color = trainColor(t.category)
    const isTracking = this.trackedTrainId === t.id
    const pos = this._trainPositions?.get(t.id)
    const movingLabel = pos ? (pos.moving ? "Moving" : "Stopped") : ""
    const movingColor = pos?.moving ? "#66bb6a" : "#ff9800"
    const speedLabel = pos?.speedKmh && pos.moving ? `~${pos.speedKmh} km/h` : ""

    const catIcon = {
      str: "fa-train-tram", Bus: "fa-bus", obu: "fa-bus",
      s: "fa-train-subway", S: "fa-train-subway",
    }[t.category] || "fa-train"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid ${catIcon}" style="margin-right:6px;"></i>${this._escapeHtml(t.name)}
      </div>
      <div class="detail-country">${this._escapeHtml(t.categoryLong || t.category)}${t.operator ? ` · ${this._escapeHtml(t.operator)}` : ""}${t.flag ? ` <span class="fi fi-${t.flag.toLowerCase()}"></span>` : ""}</div>
      <div class="detail-grid">
        ${movingLabel ? `<div class="detail-field">
          <span class="detail-label">Status</span>
          <span class="detail-value" style="color:${movingColor}">${movingLabel}</span>
        </div>` : ""}
        ${speedLabel ? `<div class="detail-field">
          <span class="detail-label">Speed</span>
          <span class="detail-value">${speedLabel}</span>
        </div>` : ""}
        ${t.direction ? `<div class="detail-field">
          <span class="detail-label">Direction</span>
          <span class="detail-value">${this._escapeHtml(t.direction)}</span>
        </div>` : ""}
        ${t.progress != null ? `<div class="detail-field">
          <span class="detail-label">Progress</span>
          <span class="detail-value">${t.progress}%</span>
        </div>` : ""}
        <div class="detail-field">
          <span class="detail-label">Position</span>
          <span class="detail-value">${t.lat.toFixed(4)}, ${t.lng.toFixed(4)}</span>
        </div>
      </div>
      <div style="display:flex;gap:6px;align-items:center;">
        <button class="detail-track-btn ${isTracking ? "tracking" : ""}" id="train-track-btn" data-train-id="${t.id}" style="flex:1;">
          ${isTracking ? "Stop Tracking" : "Track"}
        </button>
        ${isTracking ? `<button class="detail-track-btn" id="tracking-height-btn" style="flex:0;white-space:nowrap;">${this._trackingHeightLabels[this._trackingHeightIdx]}</button>` : ""}
      </div>
      ${this.signedInValue ? `<button class="detail-watch-btn" data-action="click->globe#createWatch"
        data-watch-type="entity"
        data-watch-name="Watch ${this._escapeHtml(t.name)}"
        data-watch-conditions='${JSON.stringify({ entity_type: "train", identifier: t.name, match: "name_exact" })}'>
        <i class="fa-solid fa-eye"></i> Watch
      </button>` : ""}
    `
    this.detailPanelTarget.style.display = ""

    document.getElementById("train-track-btn").addEventListener("click", (e) => {
      const tid = e.currentTarget.dataset.trainId
      if (this.trackedTrainId === tid) {
        this.stopTrainTracking()
      } else {
        this.trackTrain(tid)
      }
      const td = this._trainData?.find(tr => tr.id === tid)
      if (td) this.showTrainDetail(td)
    })
    const hBtn = document.getElementById("tracking-height-btn")
    if (hBtn) hBtn.addEventListener("click", () => {
      this.cycleTrackingHeight()
      const td = this._trainData?.find(tr => tr.id === this.trackedTrainId)
      if (td) this.showTrainDetail(td)
    })
  }

  GlobeController.prototype.trackTrain = function(id) {
    this.trackedTrainId = id
    this.stopTracking() // stop any flight tracking
    const t = this._trainData?.find(tr => tr.id === id)
    if (t) {
      const Cesium = window.Cesium
      const h = this._trackingHeights[this._trackingHeightIdx]
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(t.lng, t.lat, h),
        duration: 1.5,
      })
    }
  }

  GlobeController.prototype.stopTrainTracking = function() {
    this.trackedTrainId = null
  }
}
