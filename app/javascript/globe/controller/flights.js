import { applyFlightDetailMethods } from "globe/controller/flight_details"
import { applyFlightRenderingMethods } from "globe/controller/flight_rendering"

export function applyFlightMethods(GlobeController) {
  applyFlightRenderingMethods(GlobeController)
  applyFlightDetailMethods(GlobeController)
}
