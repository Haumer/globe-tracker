// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
import "bootstrap"
import { connectAlertsChannel } from "channels/alerts_channel"
import { connectEventsChannel } from "channels/events_channel"

// Connect ActionCable channels when DOM is ready
document.addEventListener("turbo:load", () => { connectAlertsChannel(); connectEventsChannel() })
document.addEventListener("DOMContentLoaded", () => { connectAlertsChannel(); connectEventsChannel() })
