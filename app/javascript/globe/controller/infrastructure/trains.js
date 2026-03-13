import { getDataSource, createTrainIcon, LABEL_DEFAULTS } from "../../utils"

const TRAIN_COLORS = {
  ICE: "#e53935", RJ: "#e53935", RJX: "#e53935",
  IC: "#ff9800", EC: "#ff9800",
  REX: "#66bb6a", R: "#66bb6a",
  S: "#42a5f5",
  WB: "#26c6da",
}

function trainColor(category) {
  return TRAIN_COLORS[category] || "#90a4ae"
}

export function applyTrainsMethods(GlobeController) {
  GlobeController.prototype.getTrainsDataSource = function() {
    return getDataSource(this.viewer, this._ds, "trains")
  }

  GlobeController.prototype.toggleTrains = function() {
    this.trainsVisible = this.hasTrainsToggleTarget && this.trainsToggleTarget.checked
    if (this.trainsVisible) {
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
      this._trainData = await resp.json()
      this.renderTrains()
    } catch (e) {
      console.error("Failed to fetch trains:", e)
    } finally {
      this._trainFetching = false
    }
  }

  GlobeController.prototype.renderTrains = function() {
    this._clearTrainEntities()
    if (!this._trainData || !this.trainsVisible) return

    const Cesium = window.Cesium
    const dataSource = this.getTrainsDataSource()
    const iconCache = {}

    dataSource.entities.suspendEvents()
    this._trainData.forEach(t => {
      if (!t.lat || !t.lng) return

      const color = trainColor(t.category)
      if (!iconCache[color]) iconCache[color] = createTrainIcon(color)

      const entity = dataSource.entities.add({
        id: `train-${t.id}`,
        position: Cesium.Cartesian3.fromDegrees(t.lng, t.lat, 50),
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
      this._trainEntities.push(entity)
    })
    dataSource.entities.resumeEvents()
    this._requestRender()
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

    const catIcon = {
      str: "fa-train-tram", Bus: "fa-bus", obu: "fa-bus",
      s: "fa-train-subway", S: "fa-train-subway",
    }[t.category] || "fa-train"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid ${catIcon}" style="margin-right:6px;"></i>${this._escapeHtml(t.name)}
      </div>
      <div class="detail-country">${this._escapeHtml(t.categoryLong || t.category)}</div>
      <div class="detail-grid">
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
