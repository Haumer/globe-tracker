import { applySatDetailMethods } from "./satellites/satelliteDetail"
import { applySatDataMethods } from "./satellites/satelliteData"
import { applySatHeatmapMethods } from "./satellites/satelliteHeatmap"

export function applySatelliteMethods(GlobeController) {
  applySatDetailMethods(GlobeController)
  applySatDataMethods(GlobeController)
  applySatHeatmapMethods(GlobeController)
}
