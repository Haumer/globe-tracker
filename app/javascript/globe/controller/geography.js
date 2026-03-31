import { applyGeographyBorderMethods } from "globe/controller/geography_borders"
import { applyGeographyCaptureMethods } from "globe/controller/geography_capture"
import { applyGeographyCityMethods } from "globe/controller/geography_cities"
import { applyGeographyEnvironmentMethods } from "globe/controller/geography_environment"

export function applyGeographyMethods(GlobeController) {
  applyGeographyCityMethods(GlobeController)
  applyGeographyBorderMethods(GlobeController)
  applyGeographyEnvironmentMethods(GlobeController)
  applyGeographyCaptureMethods(GlobeController)
}
