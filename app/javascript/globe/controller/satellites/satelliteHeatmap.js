import { applySatelliteFootprintMethods } from "globe/controller/satellites/satellite_footprint"
import { applySatelliteHeatmapGridMethods } from "globe/controller/satellites/satellite_heatmap_grid"
import { applySatelliteVisibilityMethods } from "globe/controller/satellites/satellite_visibility"

export function applySatHeatmapMethods(GlobeController) {
  applySatelliteHeatmapGridMethods(GlobeController)
  applySatelliteFootprintMethods(GlobeController)
  applySatelliteVisibilityMethods(GlobeController)
}
