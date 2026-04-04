import { createConsumer } from "@rails/actioncable"

let consumer = null

export function getConsumer() {
  if (!consumer) {
    // Allow an explicit cable URL override, otherwise use the app-mounted /cable endpoint.
    const meta = document.querySelector('meta[name="action-cable-url"]')
    const url = meta ? meta.content : "/cable"
    consumer = createConsumer(url)
  }
  return consumer
}

export function disconnectConsumer() {
  if (consumer) { consumer.disconnect(); consumer = null }
}
