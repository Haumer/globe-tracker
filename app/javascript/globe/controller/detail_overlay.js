import { applyDetailOverlayDisplayMethods } from "globe/controller/detail_overlay/display"
import { applyDetailOverlayGeometryMethods } from "globe/controller/detail_overlay/geometry"
import { applyDetailOverlayPayloadMethods } from "globe/controller/detail_overlay/payloads"

export function applyDetailOverlayMethods(GlobeController) {
  applyDetailOverlayDisplayMethods(GlobeController)
  applyDetailOverlayGeometryMethods(GlobeController)
  applyDetailOverlayPayloadMethods(GlobeController)
}
