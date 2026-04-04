export function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

export function firstPresent(...values) {
  return values.find(value => {
    if (value == null) return false
    if (typeof value === "number") return !Number.isNaN(value)
    return `${value}`.trim() !== ""
  })
}

export function toNumber(value) {
  if (value == null || value === "") return null
  const parsed = typeof value === "number" ? value : parseFloat(value)
  return Number.isFinite(parsed) ? parsed : null
}

export function validPoint(value) {
  return !!value && Number.isFinite(value.x) && Number.isFinite(value.y)
}

export function clampRectPosition(left, top, width, height, bounds) {
  return {
    left: clamp(left, bounds.left, bounds.right - width),
    top: clamp(top, bounds.top, bounds.bottom - height),
  }
}

export function pointDistance(a, b) {
  if (!a || !b) return Number.POSITIVE_INFINITY
  return Math.hypot(a.x - b.x, a.y - b.y)
}

export function compactFacts(values, limit = 2) {
  return values.filter(value => value != null && `${value}`.trim() !== "").slice(0, limit)
}

export function chip(label, tone = "neutral") {
  if (!label) return null
  return { label, tone }
}

export function kindLabel(kind) {
  return (kind || "item").replace(/_/g, " ").replace(/\b\w/g, char => char.toUpperCase())
}

export function shortLine(value, maxLength = 96) {
  if (value == null) return null
  const normalized = `${value}`.replace(/\s+/g, " ").trim()
  if (!normalized) return null
  if (normalized.length <= maxLength) return normalized
  return `${normalized.slice(0, Math.max(0, maxLength - 1)).trimEnd()}\u2026`
}

export function propertyValue(prop, currentTime) {
  if (prop == null) return null
  if (typeof prop.getValue === "function") {
    try {
      return prop.getValue(currentTime)
    } catch {
      return null
    }
  }
  return prop
}

export function nearFarScaleValue(nearFar, distance) {
  if (!nearFar || !Number.isFinite(distance)) return 1
  const near = Number(nearFar.near)
  const nearValue = Number(nearFar.nearValue)
  const far = Number(nearFar.far)
  const farValue = Number(nearFar.farValue)
  if (![near, nearValue, far, farValue].every(Number.isFinite)) return 1
  if (distance <= near) return nearValue
  if (distance >= far) return farValue
  if (far <= near) return farValue
  const t = (distance - near) / (far - near)
  return nearValue + (farValue - nearValue) * t
}

export function conflictPulseStroke(score) {
  if (score >= 70) return "#f44336"
  if (score >= 50) return "#ff9800"
  return "#ffc107"
}
