export const EVENT_TIMELINE_WINDOWS_MS = {
  earthquake: 24 * 60 * 60 * 1000,
  natural_event: 24 * 60 * 60 * 1000,
  news: 24 * 60 * 60 * 1000,
  gps_jamming: 60 * 60 * 1000,
  internet_outage: 24 * 60 * 60 * 1000,
  weather_alert: 48 * 60 * 60 * 1000,
  notam: 48 * 60 * 60 * 1000,
}

export const STRIKE_TIMELINE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000
export const CONFLICT_TIMELINE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000
export const EVENT_APPEAR_WINDOW_MS = 12 * 60 * 1000
export const EVENT_RENDER_BUCKET_MS = 60 * 1000
export const EVENT_ARRIVAL_PULSE_MS = 2200
export const EVENT_ARRIVAL_PULSE_BUCKET_MS = 90
export const TIMELINE_CONFLICT_BUCKET_MS = 60 * 60 * 1000
export const DEFAULT_TIMELINE_RANGE_DAYS = 7
export const TIMELINE_EVENT_DEBOUNCE_MS = {
  playing: 500,
  scrub: 250,
}
