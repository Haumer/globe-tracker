import { applySatDetailMethods } from "globe/controller/satellites/satelliteDetail"
import { applySatDataMethods } from "globe/controller/satellites/satelliteData"
import { applySatHeatmapMethods } from "globe/controller/satellites/satelliteHeatmap"

export function applySatelliteMethods(GlobeController) {
  applySatDetailMethods(GlobeController)
  applySatDataMethods(GlobeController)
  applySatHeatmapMethods(GlobeController)
}
