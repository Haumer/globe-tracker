import { applyFlightDetailMethods } from "./flight_details"
import { applyFlightRenderingMethods } from "./flight_rendering"

export function applyFlightMethods(GlobeController) {
  applyFlightRenderingMethods(GlobeController)
  applyFlightDetailMethods(GlobeController)
}
