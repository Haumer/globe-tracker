import { applySatelliteFootprintMethods } from "./satellite_footprint"
import { applySatelliteHeatmapGridMethods } from "./satellite_heatmap_grid"
import { applySatelliteVisibilityMethods } from "./satellite_visibility"

export function applySatHeatmapMethods(GlobeController) {
  applySatelliteHeatmapGridMethods(GlobeController)
  applySatelliteFootprintMethods(GlobeController)
  applySatelliteVisibilityMethods(GlobeController)
}
