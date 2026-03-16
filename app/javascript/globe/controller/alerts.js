export function applyAlertsMethods(GlobeController) {

  GlobeController.prototype._startAlertPolling = function() {
    if (!this.signedInValue) return
    this._pollAlerts()
    this._alertPollInterval = setInterval(() => this._pollAlerts(), 60000)

    // Listen for ActionCable push notifications (instant update)
    document.addEventListener("globe:new-alert", (e) => {
      // Immediately refresh from server to get full alert data
      this._pollAlerts()
    })

    // Listen for fly-to events from toast clicks
    document.addEventListener("globe:fly-to", (e) => {
      const { lat, lng, height } = e.detail
      if (lat && lng) {
        const Cesium = window.Cesium
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(lng, lat, height || 500000),
          duration: 1.5,
        })
      }
    })
  }

  GlobeController.prototype._stopAlertPolling = function() {
    if (this._alertPollInterval) {
      clearInterval(this._alertPollInterval)
      this._alertPollInterval = null
    }
  }

  GlobeController.prototype._pollAlerts = async function() {
    try {
      const resp = await fetch("/api/alerts")
      if (!resp.ok) return
      const data = await resp.json()
      const hadUnseen = this._alertUnseenCount || 0
      this._alertData = data.alerts || []
      this._alertUnseenCount = data.unseen_count || 0
      this._renderAlertBadge()
      // Flash badge on new alerts
      if (this._alertUnseenCount > hadUnseen && hadUnseen >= 0) {
        this._flashAlertBadge()
      }
      // Update panel content if alerts tab is active
      if (this.hasAlertFeedContentTarget && this.hasRightPanelTarget) {
        const activePane = this.rightPanelTarget.querySelector(".rp-pane--active")
        if (activePane?.dataset.rpPane === "alerts") {
          this._renderAlertFeed()
        }
      }
      if (this._syncRightPanels) this._syncRightPanels()
    } catch (e) {
      console.warn("Alert poll failed:", e)
    }
  }

  GlobeController.prototype._renderAlertBadge = function() {
    const badge = document.getElementById("stat-alert-badge")
    if (!badge) return
    const count = this._alertUnseenCount || 0
    badge.textContent = count
    badge.style.display = count > 0 ? "" : "none"
  }

  GlobeController.prototype._flashAlertBadge = function() {
    const badge = document.getElementById("stat-alert-badge")
    if (!badge) return
    badge.classList.add("alert-badge--pulse")
    setTimeout(() => badge.classList.remove("alert-badge--pulse"), 2000)
  }

  GlobeController.prototype.toggleAlertsFeed = function() {
    if (this._alertData?.length > 0) {
      this._showRightPanel("alerts")
    }
  }

  GlobeController.prototype._renderAlertFeed = function() {
    if (!this.hasAlertFeedContentTarget) return
    const alerts = this._alertData || []

    if (alerts.length === 0) {
      this.alertFeedContentTarget.innerHTML = '<div class="alert-empty">No alerts yet. Create watches to monitor entities, areas, and events.</div>'
      return
    }

    const html = alerts.map(a => {
      const timeAgo = this._timeAgo(new Date(a.created_at))
      const unseenClass = a.seen ? "" : " alert-card--unseen"
      const icon = this._alertIcon(a.entity_type)
      const color = this._alertColor(a.entity_type)

      return `<div class="alert-card${unseenClass}" data-alert-id="${a.id}">
        <div class="alert-card-bar" style="background:${color};"></div>
        <div class="alert-card-body">
          <div class="alert-card-header">
            <span class="alert-card-icon" style="color:${color}"><i class="fa-solid ${icon}"></i></span>
            <span class="alert-card-title">${this._escapeHtml(a.title)}</span>
          </div>
          <div class="alert-card-time">${timeAgo}</div>
          <div class="alert-card-actions">
            ${a.lat != null ? `<button class="alert-action-btn" data-action="click->globe#focusAlert" data-alert-lat="${a.lat}" data-alert-lng="${a.lng}" data-alert-entity-type="${a.entity_type || ""}" data-alert-entity-id="${a.entity_id || ""}"><i class="fa-solid fa-location-crosshairs"></i> Focus</button>` : ""}
            ${!a.seen ? `<button class="alert-action-btn" data-action="click->globe#dismissAlert" data-alert-id="${a.id}"><i class="fa-solid fa-check"></i> Dismiss</button>` : ""}
          </div>
        </div>
      </div>`
    }).join("")

    this.alertFeedContentTarget.innerHTML = html
  }

  GlobeController.prototype._alertIcon = function(entityType) {
    const icons = {
      flight: "fa-plane",
      ship: "fa-ship",
      earthquake: "fa-house-crack",
      conflict: "fa-crosshairs",
      satellite: "fa-satellite",
    }
    return icons[entityType] || "fa-bell"
  }

  GlobeController.prototype._alertColor = function(entityType) {
    const colors = {
      flight: "#4fc3f7",
      ship: "#26c6da",
      earthquake: "#ff7043",
      conflict: "#f44336",
      satellite: "#ab47bc",
    }
    return colors[entityType] || "#ffd54f"
  }

  GlobeController.prototype.focusAlert = function(event) {
    const lat = parseFloat(event.currentTarget.dataset.alertLat)
    const lng = parseFloat(event.currentTarget.dataset.alertLng)
    if (isNaN(lat) || isNaN(lng)) return
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 500000),
      duration: 1.5,
    })
  }

  GlobeController.prototype.dismissAlert = async function(event) {
    const id = event.currentTarget.dataset.alertId
    try {
      await fetch(`/api/alerts/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this._csrfToken() },
        body: JSON.stringify({ seen: true }),
      })
      // Remove from local data entirely
      this._alertData = this._alertData.filter(a => a.id !== parseInt(id))
      this._alertUnseenCount = Math.max(0, (this._alertUnseenCount || 0) - 1)
      this._renderAlertBadge()
      this._renderAlertFeed()
    } catch (e) {
      console.warn("Failed to dismiss alert:", e)
    }
  }

  GlobeController.prototype.markAllAlertsSeen = async function() {
    try {
      await fetch("/api/alerts/mark_all_seen", {
        method: "POST",
        headers: { "X-CSRF-Token": this._csrfToken() },
      })
      this._alertData.forEach(a => a.seen = true)
      this._alertUnseenCount = 0
      this._renderAlertBadge()
      this._renderAlertFeed()
    } catch (e) {
      console.warn("Failed to mark all seen:", e)
    }
  }

  GlobeController.prototype.createWatch = async function(event) {
    const btn = event.currentTarget
    const watchType = btn.dataset.watchType
    let conditions
    try { conditions = JSON.parse(btn.dataset.watchConditions) } catch { return }

    const name = btn.dataset.watchName || conditions.identifier || "New watch"

    try {
      const resp = await fetch("/api/watches", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this._csrfToken() },
        body: JSON.stringify({ name, watch_type: watchType, conditions }),
      })
      if (resp.ok) {
        this._toast("Watch created — you'll be alerted when conditions match")
        setTimeout(() => this._toastHide(), 3000)
      } else {
        const data = await resp.json()
        this._toast(`Watch failed: ${data.errors?.join(", ")}`)
        setTimeout(() => this._toastHide(), 4000)
      }
    } catch (e) {
      console.warn("Failed to create watch:", e)
    }
  }

  GlobeController.prototype.createAreaWatch = function() {
    if (!this.signedInValue) return
    // Build watch from current selection (countries or circle)
    const conditions = { entity_types: [], filters: {} }

    if (this._activeCircle) {
      const center = this._activeCircle.center
      const r = this._activeCircle.radius / 111000 // rough degrees
      conditions.bounds = [
        center.lat - r, center.lng - r,
        center.lat + r, center.lng + r,
      ]
    } else if (this.selectedCountries?.size > 0) {
      // Use rough country bounds — the server will filter
      conditions.countries = [...this.selectedCountries]
    } else {
      this._toast("Select a country or draw a circle first")
      setTimeout(() => this._toastHide(), 3000)
      return
    }

    if (this.flightsVisible) conditions.entity_types.push("flight")
    if (this.shipsVisible) conditions.entity_types.push("ship")
    if (conditions.entity_types.length === 0) conditions.entity_types.push("flight")

    const name = this._activeCircle
      ? "Circle area watch"
      : `${[...this.selectedCountries].join(", ")} watch`

    const btn = document.createElement("button")
    btn.dataset.watchType = "area"
    btn.dataset.watchConditions = JSON.stringify(conditions)
    btn.dataset.watchName = name
    this.createWatch({ currentTarget: btn })
  }

  GlobeController.prototype._csrfToken = function() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
