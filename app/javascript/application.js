// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
import "bootstrap"
import { connectAlertsChannel } from "channels/alerts_channel"
import { connectEventsChannel } from "channels/events_channel"

// Only connect ActionCable on the globe page (avoid wasting Puma threads on static pages)
function connectIfGlobe() {
  if (!document.body.classList.contains("globe-page")) return
  connectEventsChannel()
  connectAlertsChannel()
}
document.addEventListener("turbo:load", connectIfGlobe)
