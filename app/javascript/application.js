// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
import "bootstrap"
import { connectAlertsChannel } from "channels/alerts_channel"

// Connect ActionCable alerts when DOM is ready
document.addEventListener("turbo:load", () => connectAlertsChannel())
document.addEventListener("DOMContentLoaded", () => connectAlertsChannel())
