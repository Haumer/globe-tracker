import { applyCoreMethods } from "globe/controller/core"
import { applyDetailOverlayMethods } from "globe/controller/detail_overlay"
import { applyFlightMethods } from "globe/controller/flights"
import { applySelectionMethods } from "globe/controller/selection"
import { applySatelliteMethods } from "globe/controller/satellites"
import { applySituationalMethods } from "globe/controller/situational"
import { applyMaritimeMethods } from "globe/controller/maritime"
import { applyGeographyMethods } from "globe/controller/geography"
import { applyUiMethods } from "globe/controller/ui/index"
import { applyNewsMethods } from "globe/controller/news"
import { applyInfrastructureMethods } from "globe/controller/infrastructure"
import { applyTimelineMethods } from "globe/controller/timeline"
import { applyWorkspaceMethods } from "globe/controller/workspaces"
import { applyAlertsMethods } from "globe/controller/alerts"
import { applyConnectionsMethods } from "globe/controller/connections"
import { applyMiniTimelineMethods } from "globe/controller/mini_timeline"
import { applyFiresMethods } from "globe/controller/fires"
import { applyWeatherMethods } from "globe/controller/weather"
import { applyInsightsMethods } from "globe/controller/insights"
import { applyFinancialMethods } from "globe/controller/financial"
import { applyRegionMethods } from "globe/controller/regions"
import { applyContextMethods } from "globe/controller/context"

export function applyGlobeControllerMixins(GlobeController) {
  applyCoreMethods(GlobeController)
  applyDetailOverlayMethods(GlobeController)
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
  applyContextMethods(GlobeController)
}
