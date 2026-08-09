// The news pin, drawn rather than pointed.
//
// A Cesium `point` can only be a filled circle with an outline, so every signal
// the pin carries had to be squeezed into fill alpha and outline width -- which
// is how "we don't know exactly where this happened" ended up encoded as
// faintness, indistinguishable from the globe simply being bright there. Drawing
// the mark onto a canvas and using it as a billboard gives it parts:
//
//   ring          category, always present -- this is the mark's footprint
//   centre        we know where it happened; absent means country-level only
//   outer tick    escalated, achromatic so it cannot be read as a category
//   casing        a dark stroke under everything, so the mark survives both the
//                 daylit hemisphere and the night side
//
// Structure only resolves from continent zoom in. At whole-globe zoom a pin is
// three or four pixels and degrades to a coloured speck, which is the right
// thing for it to degrade to.

// Everything is drawn once at this size and scaled down per pin, so marks are
// always downsampled and never soft.
export const PIN_CANVAS_PX = 64

// Ring geometry, in canvas pixels from the centre.
const RING_RADIUS = 22
const RING_WIDTH = 10.5
const CENTRE_RADIUS = 8.5
const ESCALATION_RADIUS = 29
const ESCALATION_WIDTH = 3
const CASING_WIDTH = 2

// One canvas per distinct mark. Cesium keys its texture atlas on the image
// object, so handing back the same canvas for the same mark reuses the texture
// instead of allocating a new one per pin.
const CACHE = new Map()

function circle(ctx, radius, { stroke, fill, width }) {
  ctx.beginPath()
  ctx.arc(PIN_CANVAS_PX / 2, PIN_CANVAS_PX / 2, radius, 0, Math.PI * 2)
  if (fill) {
    ctx.fillStyle = fill
    ctx.fill()
  }
  if (stroke) {
    ctx.lineWidth = width
    ctx.strokeStyle = stroke
    ctx.stroke()
  }
}

function draw({ color, located, escalated, selected }) {
  const canvas = document.createElement("canvas")
  canvas.width = PIN_CANVAS_PX
  canvas.height = PIN_CANVAS_PX
  const ctx = canvas.getContext("2d")

  const casing = "rgba(0, 0, 0, 0.55)"

  // Casing first, wider than each element it sits under.
  circle(ctx, RING_RADIUS, { stroke: casing, width: RING_WIDTH + CASING_WIDTH * 2 })
  if (located) circle(ctx, CENTRE_RADIUS + CASING_WIDTH / 2, { fill: casing })

  circle(ctx, RING_RADIUS, { stroke: color, width: RING_WIDTH })

  // A filled centre is the claim that we know the spot. An empty one is the
  // honest version of the old 0.3-alpha wash: same hue, same size, no centre.
  if (located) circle(ctx, CENTRE_RADIUS, { fill: color })

  if (escalated) {
    circle(ctx, ESCALATION_RADIUS, { stroke: casing, width: ESCALATION_WIDTH + CASING_WIDTH })
    circle(ctx, ESCALATION_RADIUS, { stroke: "rgba(255, 255, 255, 0.92)", width: ESCALATION_WIDTH })
  }

  // Selection is a ring outside everything else, so it reads as "this one" on
  // top of whatever the pin was already saying.
  if (selected) {
    circle(ctx, ESCALATION_RADIUS + 2.5, { stroke: casing, width: 5 })
    circle(ctx, ESCALATION_RADIUS + 2.5, { stroke: "#ffffff", width: 3 })
  }

  return canvas
}

export function newsPinIcon({ color, located = false, escalated = false, selected = false }) {
  const key = `${color}|${located ? 1 : 0}|${escalated ? 1 : 0}|${selected ? 1 : 0}`
  let canvas = CACHE.get(key)
  if (!canvas) {
    canvas = draw({ color, located, escalated, selected })
    CACHE.set(key, canvas)
  }
  return canvas
}

// The mark's ink spans roughly this fraction of the canvas, so a pin asked for
// "18 pixels" gets 18 pixels of visible mark rather than 18 pixels of mostly
// transparent canvas.
const INK_FRACTION = (ESCALATION_RADIUS + 4) * 2 / PIN_CANVAS_PX

export function newsPinScale(pixelSize) {
  return (pixelSize / PIN_CANVAS_PX) / INK_FRACTION
}
