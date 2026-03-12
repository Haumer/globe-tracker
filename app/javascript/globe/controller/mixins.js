import { applyCoreMethods } from "./core"
import { applyFlightMethods } from "./flights"
import { applySelectionMethods } from "./selection"
import { applySatelliteMethods } from "./satellites"
import { applySituationalMethods } from "./situational"
import { applyMaritimeMethods } from "./maritime"
import { applyGeographyMethods } from "./geography"
import { applyUiMethods } from "./ui"
import { applyNewsMethods } from "./news"
import { applyInfrastructureMethods } from "./infrastructure"
import { applyTimelineMethods } from "./timeline"
import { applyWorkspaceMethods } from "./workspaces"

export function applyGlobeControllerMixins(GlobeController) {
  applyCoreMethods(GlobeController)
  applyFlightMethods(GlobeController)
  applySelectionMethods(GlobeController)
  applySatelliteMethods(GlobeController)
  applySituationalMethods(GlobeController)
  applyMaritimeMethods(GlobeController)
  applyGeographyMethods(GlobeController)
  applyUiMethods(GlobeController)
  applyNewsMethods(GlobeController)
  applyInfrastructureMethods(GlobeController)
  applyTimelineMethods(GlobeController)
  applyWorkspaceMethods(GlobeController)
}
