import { createConsumer } from "@rails/actioncable"

let consumer = null
let subscription = null

export function connectEventsChannel() {
  if (consumer) return
  consumer = createConsumer()

  subscription = consumer.subscriptions.create("EventsChannel", {
    connected() {},
    disconnected() {},

    received(data) {
      if (data.type === "earthquake") {
        showEventToast("earthquake", data)
      } else if (data.type === "conflict_escalation") {
        showEventToast("conflict", data)
      } else if (data.type === "gps_jamming") {
        showEventToast("jamming", data)
      }

      // Dispatch to globe controller for immediate data refresh
      document.dispatchEvent(new CustomEvent("globe:breaking-event", { detail: data }))
    },
  })
}

function showEventToast(kind, data) {
  const container = document.getElementById("alert-toasts") || createToastContainer()

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

export function disconnectEventsChannel() {
  if (subscription) { subscription.unsubscribe(); subscription = null }
  if (consumer) { consumer.disconnect(); consumer = null }
}
