// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
import "bootstrap"
import { connectAlertsChannel } from "channels/alerts_channel"
import { connectEventsChannel } from "channels/events_channel"

const APP_VERSION_CHECK_MS = 15_000
const INITIAL_APP_VERSION_CHECK_MS = 3_000
const APP_RELOAD_REVISION_STORAGE_KEY = "gt-app-reload-revision"

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
      const lastReloadedRevision = window.sessionStorage?.getItem(APP_RELOAD_REVISION_STORAGE_KEY)
      if (lastReloadedRevision === data.revision) return

      window.sessionStorage?.setItem(APP_RELOAD_REVISION_STORAGE_KEY, data.revision)
      window.location.reload()
    }
  } catch (_error) {
    // Best-effort only. Ignore transient network failures.
  }
}

function startAppVersionWatcher() {
  if (appVersionWatcherStarted) return
  appVersionWatcherStarted = true

  window.setTimeout(checkForAppUpdate, INITIAL_APP_VERSION_CHECK_MS)
  window.setInterval(checkForAppUpdate, APP_VERSION_CHECK_MS)
  window.addEventListener("focus", checkForAppUpdate)
  window.addEventListener("pageshow", checkForAppUpdate)
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") checkForAppUpdate()
  })
}

document.addEventListener("turbo:load", () => {
  knownAppRevision = currentAppRevision()
  if (knownAppRevision) {
    const lastReloadedRevision = window.sessionStorage?.getItem(APP_RELOAD_REVISION_STORAGE_KEY)
    if (lastReloadedRevision === knownAppRevision) {
      window.sessionStorage?.removeItem(APP_RELOAD_REVISION_STORAGE_KEY)
    }
  }
  connectIfGlobe()
  startAppVersionWatcher()
})
