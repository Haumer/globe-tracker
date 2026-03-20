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
import { applyAlertsMethods } from "./alerts"
import { applyConnectionsMethods } from "./connections"
import { applyMiniTimelineMethods } from "./mini_timeline"
import { applyFiresMethods } from "./fires"
import { applyWeatherMethods } from "./weather"
import { applyInsightsMethods } from "./insights"
import { applyFinancialMethods } from "./financial"
import { applyRegionMethods } from "./regions"

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
  applyAlertsMethods(GlobeController)
  applyConnectionsMethods(GlobeController)
  applyMiniTimelineMethods(GlobeController)
  applyFiresMethods(GlobeController)
  applyWeatherMethods(GlobeController)
  applyInsightsMethods(GlobeController)
  applyFinancialMethods(GlobeController)
  applyRegionMethods(GlobeController)
}
