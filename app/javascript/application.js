// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
import "bootstrap"
import { connectAlertsChannel } from "channels/alerts_channel"
import { connectEventsChannel } from "channels/events_channel"

const APP_VERSION_CHECK_MS = 60_000

// Only connect ActionCable on the globe page (avoid wasting Puma threads on static pages)
function connectIfGlobe() {
  if (!document.body.classList.contains("globe-page")) return
  connectEventsChannel()
  connectAlertsChannel()
}

function currentAppRevision() {
  return document.querySelector('meta[name="app-revision"]')?.content || ""
}

let knownAppRevision = ""
let appVersionWatcherStarted = false

async function checkForAppUpdate() {
  if (!knownAppRevision) return

  try {
    const response = await fetch("/version", {
      cache: "no-store",
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    })
    if (!response.ok) return

    const data = await response.json()
    if (data?.revision && data.revision !== knownAppRevision) {
      window.location.reload()
    }
  } catch (_error) {
    // Best-effort only. Ignore transient network failures.
  }
}

function startAppVersionWatcher() {
  if (appVersionWatcherStarted) return
  appVersionWatcherStarted = true

  window.setInterval(checkForAppUpdate, APP_VERSION_CHECK_MS)
  window.addEventListener("focus", checkForAppUpdate)
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") checkForAppUpdate()
  })
}

document.addEventListener("turbo:load", () => {
  knownAppRevision = currentAppRevision()
  connectIfGlobe()
  startAppVersionWatcher()
})
