export function applyCoreUiHelpers(GlobeController) {
  GlobeController.prototype._toast = function(msg, type) {
    const el = document.getElementById("gt-toast")
    if (!el) return
    clearTimeout(this._toastTimer)
    el.classList.remove("visible", "gt-toast--success", "gt-toast--error")
    el.innerHTML = ""
    if (type === "success") el.classList.add("gt-toast--success")
    if (type === "error") el.classList.add("gt-toast--error")

    const span = document.createElement("span")
    span.textContent = msg
    el.appendChild(span)

    if (type === "error") {
      const closeBtn = document.createElement("button")
      closeBtn.className = "gt-toast-close"
      closeBtn.innerHTML = "&times;"
      closeBtn.setAttribute("aria-label", "Dismiss")
      closeBtn.addEventListener("click", () => this._toastHide())
      el.appendChild(closeBtn)
      el.style.pointerEvents = "auto"
    } else {
      el.style.pointerEvents = "none"
    }

    el.classList.add("visible")
    if (type !== "error") {
      this._toastTimer = setTimeout(() => el.classList.remove("visible"), 2000)
    }
  }

  GlobeController.prototype._toastHide = function() {
    const el = document.getElementById("gt-toast")
    if (!el) return
    el.classList.remove("visible", "gt-toast--success", "gt-toast--error")
    el.style.pointerEvents = "none"
    clearTimeout(this._toastTimer)
  }

  GlobeController.prototype._showLoading = function(panelKey) {
    const targetKey = panelKey + "Loading"
    if (this[`has${targetKey[0].toUpperCase()}${targetKey.slice(1)}Target`]) {
      this[`${targetKey}Target`].style.display = ""
    }
    const emptyKey = panelKey + "Empty"
    if (this[`has${emptyKey[0].toUpperCase()}${emptyKey.slice(1)}Target`]) {
      this[`${emptyKey}Target`].style.display = "none"
    }
  }

  GlobeController.prototype._hideLoading = function(panelKey, itemCount) {
    const targetKey = panelKey + "Loading"
    if (this[`has${targetKey[0].toUpperCase()}${targetKey.slice(1)}Target`]) {
      this[`${targetKey}Target`].style.display = "none"
    }
    const emptyKey = panelKey + "Empty"
    if (this[`has${emptyKey[0].toUpperCase()}${emptyKey.slice(1)}Target`]) {
      this[`${emptyKey}Target`].style.display = itemCount === 0 ? "" : "none"
    }
  }

  GlobeController.prototype._handleBackgroundRefresh = function(resp, key, hasData, retryFn) {
    const queued = resp.headers.get("X-Background-Refresh") === "queued"
    if (!queued || hasData) {
      if (this._backgroundRefreshRetryTimers[key]) {
        clearTimeout(this._backgroundRefreshRetryTimers[key])
        delete this._backgroundRefreshRetryTimers[key]
      }
      delete this._backgroundRefreshRetryCounts[key]
      return
    }

    const attempts = this._backgroundRefreshRetryCounts[key] || 0
    if (attempts >= 3) return

    if (this._backgroundRefreshRetryTimers[key]) {
      clearTimeout(this._backgroundRefreshRetryTimers[key])
    }

    this._backgroundRefreshRetryCounts[key] = attempts + 1
    this._backgroundRefreshRetryTimers[key] = setTimeout(() => {
      delete this._backgroundRefreshRetryTimers[key]
      retryFn()
    }, 1500)
  }

  GlobeController.prototype._timeAgo = function(date) {
    const seconds = Math.floor((Date.now() - date.getTime()) / 1000)
    if (seconds < 60) return "just now"
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
    return `${Math.floor(seconds / 86400)}d ago`
  }

  GlobeController.prototype._parseDateValue = function(value) {
    if (!value) return null
    const date = value instanceof Date ? value : new Date(value)
    return Number.isNaN(date.getTime()) ? null : date
  }

  GlobeController.prototype._statusTone = function(status) {
    switch (status) {
      case "ready":
      case "available":
      case "fetched":
        return { color: "#66bb6a", background: "rgba(102,187,106,0.14)" }
      case "pending":
        return { color: "#4fc3f7", background: "rgba(79,195,247,0.14)" }
      case "stale":
        return { color: "#ffb300", background: "rgba(255,179,0,0.16)" }
      case "error":
      case "failed":
        return { color: "#ef5350", background: "rgba(239,83,80,0.16)" }
      case "unavailable":
      default:
        return { color: "#90a4ae", background: "rgba(144,164,174,0.16)" }
    }
  }

  GlobeController.prototype._statusLabel = function(status, kind = "snapshot") {
    switch (status) {
      case "ready":
        return `ready ${kind}`
      case "available":
        return `${kind} ready`
      case "pending":
        return `${kind} pending`
      case "stale":
        return `stale ${kind}`
      case "error":
        return `${kind} error`
      case "failed":
      case "unavailable":
        return `${kind} unavailable`
      default:
        return kind
    }
  }

  GlobeController.prototype._statusChip = function(status, label = null) {
    const tone = this._statusTone(status)
    const text = label || this._statusLabel(status).toUpperCase()
    return `<span class="detail-chip" style="background:${tone.background};color:${tone.color};">${this._escapeHtml(text.toUpperCase())}</span>`
  }

  GlobeController.prototype._cacheMeta = function(fetchedAt, expiresAt) {
    const fetched = this._parseDateValue(fetchedAt)
    const expires = this._parseDateValue(expiresAt)
    const parts = []
    if (fetched) parts.push(`updated ${this._timeAgo(fetched)}`)
    if (expires) parts.push(expires.getTime() > Date.now() ? "cache fresh" : "cache stale")
    return parts.join(" · ")
  }

  GlobeController.prototype._escapeHtml = function(str) {
    if (!str) return ""
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  GlobeController.prototype._safeUrl = function(url) {
    if (!url) return "#"
    const value = String(url).trim()
    if (/^https?:\/\//i.test(value)) return this._escapeHtml(value)
    return "#"
  }
}
