import { createConsumer } from "@rails/actioncable"

let consumer = null
let subscription = null

export function connectAlertsChannel() {
  // Only connect for signed-in users
  if (!document.querySelector('meta[name="current-user-id"]')) return

  if (consumer) return // Already connected
  consumer = createConsumer()

  subscription = consumer.subscriptions.create("AlertsChannel", {
    connected() {},

    disconnected() {},

    received(data) {
      if (data.type === "new_alert") {
        handleNewAlert(data.alert)
      } else if (data.type === "badge_update") {
        updateBadge(data.unseen_count)
      }
    },
  })
}

function handleNewAlert(alert) {
  // Show toast notification
  showAlertToast(alert)

  // Update badge count
  const badge = document.getElementById("stat-alert-badge")
  if (badge) {
    const current = parseInt(badge.textContent) || 0
    badge.textContent = current + 1
    badge.style.display = ""
  }

  // Dispatch custom event for globe controller to handle
  document.dispatchEvent(new CustomEvent("globe:new-alert", { detail: alert }))
}

function updateBadge(count) {
  const badge = document.getElementById("stat-alert-badge")
  if (badge) {
    badge.textContent = count
    badge.style.display = count > 0 ? "" : "none"
  }
}

function showAlertToast(alert) {
  const container = document.getElementById("alert-toasts") || createToastContainer()

  const toast = document.createElement("div")
  toast.className = "alert-toast"
  toast.innerHTML = `
    <div class="alert-toast-icon"><i class="fa-solid fa-bell"></i></div>
    <div class="alert-toast-body">
      <div class="alert-toast-title">${escapeHtml(alert.title)}</div>
      ${alert.watch_name ? `<div class="alert-toast-watch">${escapeHtml(alert.watch_name)}</div>` : ""}
    </div>
    <button class="alert-toast-close" onclick="this.parentElement.remove()">&times;</button>
  `

  // Click to fly to location
  if (alert.lat && alert.lng) {
    toast.style.cursor = "pointer"
    toast.addEventListener("click", (e) => {
      if (e.target.classList.contains("alert-toast-close")) return
      document.dispatchEvent(new CustomEvent("globe:fly-to", {
        detail: { lat: alert.lat, lng: alert.lng, height: 500000 },
      }))
      toast.remove()
    })
  }

  container.appendChild(toast)

  // Auto-dismiss after 8 seconds
  setTimeout(() => {
    toast.classList.add("alert-toast-fade")
    setTimeout(() => toast.remove(), 300)
  }, 8000)
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

export function disconnectAlertsChannel() {
  if (subscription) {
    subscription.unsubscribe()
    subscription = null
  }
  if (consumer) {
    consumer.disconnect()
    consumer = null
  }
}
