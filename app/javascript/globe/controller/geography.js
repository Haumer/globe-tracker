import { applyGeographyBorderMethods } from "./geography_borders"
import { applyGeographyCaptureMethods } from "./geography_capture"
import { applyGeographyCityMethods } from "./geography_cities"
import { applyGeographyEnvironmentMethods } from "./geography_environment"

export function applyGeographyMethods(GlobeController) {
  applyGeographyCityMethods(GlobeController)
  applyGeographyBorderMethods(GlobeController)
  applyGeographyEnvironmentMethods(GlobeController)
  applyGeographyCaptureMethods(GlobeController)
}
