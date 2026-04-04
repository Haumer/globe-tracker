import { getConsumer } from "channels/consumer"

let subscription = null
const EVENT_TOAST_TTLS = {
  earthquake: 2 * 60 * 1000,
  conflict: 15 * 60 * 1000,
  jamming: 5 * 60 * 1000,
}
const MAX_EVENT_TOASTS = 3
const recentEventTimestamps = new Map()

export function connectEventsChannel() {
  if (subscription) return
  const consumer = getConsumer()

  subscription = consumer.subscriptions.create("EventsChannel", {
    connected() {},
    disconnected() {},

    received(data) {
      const kind = eventKindFor(data.type)
      if (!kind) return
      const gate = gateIncomingEvent(kind, data)

      if (gate.showToast) showEventToast(kind, data, gate.key)
      if (gate.dispatch) {
        document.dispatchEvent(new CustomEvent("globe:breaking-event", { detail: data }))
      }
    },
  })
}

function showEventToast(kind, data, eventKey = null) {
  const container = document.getElementById("alert-toasts") || createToastContainer()
  removeExistingEventToast(container, eventKey)

  const configs = {
    earthquake: {
      icon: "fa-house-crack",
      color: "#ff7043",
      title: `M${data.data?.mag} Earthquake`,
      detail: data.data?.title,
    },
    conflict: {
      icon: "fa-crosshairs",
      color: "#f44336",
      title: `${(data.data?.trend || "").toUpperCase()} — ${data.data?.situation || "Conflict Zone"}`,
      detail: data.data?.headline,
    },
    jamming: {
      icon: "fa-satellite-dish",
      color: "#ff9800",
      title: `GPS Jamming ${data.data?.level?.toUpperCase()}`,
      detail: `${data.data?.pct}% interference detected`,
    },
  }

  const cfg = configs[kind] || { icon: "fa-bolt", color: "#fff", title: "Breaking Event", detail: "" }

  const toast = document.createElement("div")
  toast.className = "alert-toast"
  toast.dataset.toastSource = "events"
  if (eventKey) toast.dataset.eventKey = eventKey
  toast.style.borderLeftColor = cfg.color
  toast.innerHTML = `
    <div class="alert-toast-icon" style="color:${cfg.color}"><i class="fa-solid ${cfg.icon}"></i></div>
    <div class="alert-toast-body">
      <div class="alert-toast-title" style="color:${cfg.color}">${escapeHtml(cfg.title)}</div>
      ${cfg.detail ? `<div class="alert-toast-watch">${escapeHtml(cfg.detail?.substring(0, 80))}</div>` : ""}
    </div>
    <button class="alert-toast-close" onclick="this.parentElement.remove()">&times;</button>
  `

  // Click to fly to location
  const lat = data.data?.lat
  const lng = data.data?.lng
  if (lat && lng) {
    toast.style.cursor = "pointer"
    toast.addEventListener("click", (e) => {
      if (e.target.classList.contains("alert-toast-close")) return
      document.dispatchEvent(new CustomEvent("globe:fly-to", {
        detail: { lat, lng, height: kind === "earthquake" ? 800000 : 2000000 },
      }))
      toast.remove()
    })
  }

  container.appendChild(toast)
  trimEventToasts(container)
  setTimeout(() => {
    toast.classList.add("alert-toast-fade")
    setTimeout(() => toast.remove(), 300)
  }, 10000)
}

function createToastContainer() {
  const container = document.createElement("div")
  container.id = "alert-toasts"
  document.body.appendChild(container)
  return container
}

function escapeHtml(str) {
  if (!str) return ""
  const div = document.createElement("div")
  div.textContent = str
  return div.innerHTML
}

function eventKindFor(type) {
  if (type === "earthquake") return "earthquake"
  if (type === "conflict_escalation") return "conflict"
  if (type === "gps_jamming") return "jamming"
  return null
}

function gateIncomingEvent(kind, payload) {
  const key = buildEventKey(kind, payload)
  if (!key) return { key: null, showToast: true, dispatch: true }

  const now = Date.now()
  pruneRecentEvents(now)
  const ttl = EVENT_TOAST_TTLS[kind] || 2 * 60 * 1000
  const lastSeenAt = recentEventTimestamps.get(key)

  if (lastSeenAt && now - lastSeenAt < ttl) {
    return { key, showToast: false, dispatch: false }
  }

  recentEventTimestamps.set(key, now)
  return { key, showToast: true, dispatch: true }
}

function pruneRecentEvents(now = Date.now()) {
  const maxTtl = Math.max(...Object.values(EVENT_TOAST_TTLS))
  for (const [key, ts] of recentEventTimestamps.entries()) {
    if (now - ts > maxTtl) recentEventTimestamps.delete(key)
  }
}

function buildEventKey(kind, payload) {
  const data = payload?.data || {}

  if (kind === "conflict") {
    const cellKey = normalizeKeyPart(data.cell_key)
    if (cellKey) return `conflict:${cellKey}:${normalizeKeyPart(data.trend)}`
    return [
      "conflict",
      normalizeKeyPart(data.situation),
      normalizeKeyPart(data.theater),
      normalizeKeyPart(data.trend),
    ].join(":")
  }

  if (kind === "earthquake") {
    const locationKey = data.id || `${roundCoord(data.lat)},${roundCoord(data.lng)}`
    return `earthquake:${locationKey}:${normalizeKeyPart(data.mag)}`
  }

  if (kind === "jamming") {
    return `jamming:${roundCoord(data.lat)},${roundCoord(data.lng)}:${normalizeKeyPart(data.level)}`
  }

  return null
}

function normalizeKeyPart(value) {
  return String(value ?? "").trim().toLowerCase().replace(/\s+/g, "-")
}

function roundCoord(value) {
  const number = Number(value)
  if (!Number.isFinite(number)) return "na"
  return number.toFixed(2)
}

function removeExistingEventToast(container, eventKey) {
  if (!eventKey) return
  Array.from(container.querySelectorAll(".alert-toast[data-toast-source='events']")).forEach(toast => {
    if (toast.dataset.eventKey === eventKey) toast.remove()
  })
}

function trimEventToasts(container) {
  while (true) {
    const toasts = Array.from(container.querySelectorAll(".alert-toast[data-toast-source='events']"))
    if (toasts.length <= MAX_EVENT_TOASTS) return
    toasts[0].remove()
  }
}

export function disconnectEventsChannel() {
  if (subscription) { subscription.unsubscribe(); subscription = null }
}
