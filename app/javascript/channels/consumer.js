import { createConsumer } from "@rails/actioncable"

let consumer = null

export function getConsumer() {
  if (!consumer) {
    // Use the action-cable-url meta tag (set by AnyCable to point at the Go server)
    const meta = document.querySelector('meta[name="action-cable-url"]')
    const url = meta ? meta.content : "/cable"
    consumer = createConsumer(url)
  }
  return consumer
}

export function disconnectConsumer() {
  if (consumer) { consumer.disconnect(); consumer = null }
}
