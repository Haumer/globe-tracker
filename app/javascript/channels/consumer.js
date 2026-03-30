import { createConsumer } from "@rails/actioncable"

let consumer = null

export function getConsumer() {
  if (!consumer) {
    // Use the Rails Action Cable meta tag so dev and prod share the same connection path.
    const meta = document.querySelector('meta[name="action-cable-url"]')
    const url = meta ? meta.content : "/cable"
    consumer = createConsumer(url)
  }
  return consumer
}

export function disconnectConsumer() {
  if (consumer) { consumer.disconnect(); consumer = null }
}
