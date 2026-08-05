export const OBSERVER_SATELLITE_CATEGORIES = Object.freeze([
  "weather",
  "resource",
  "planet",
  "radar",
  "dmc",
  "geo",
  "analyst",
  "military",
])

export function satelliteCategoryLoadKey(category, observing = false) {
  return observing ? `${category}:observing` : category
}
