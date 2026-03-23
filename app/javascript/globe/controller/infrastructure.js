import { applyGpsJammingMethods } from "./infrastructure/gpsJamming"
import { applyCablesMethods } from "./infrastructure/submarineCables"
import { applyOutagesMethods } from "./infrastructure/internetOutages"
import { applyPowerPlantsMethods } from "./infrastructure/powerPlants"
import { applyConflictsMethods } from "./infrastructure/conflictEvents"
import { applyNotamsMethods } from "./infrastructure/notams"
import { applyTrafficMethods } from "./infrastructure/internetTraffic"
import { applyPipelinesMethods } from "./infrastructure/pipelines"
import { applyRailwaysMethods } from "./infrastructure/railways"
import { applyTrainsMethods } from "./infrastructure/trains"
import { applyConflictPulseMethods } from "./infrastructure/conflictPulse"
import { applyChokepointsMethods } from "./infrastructure/chokepoints"
import { applyStrikesMethods } from "./infrastructure/strikes"

export function applyInfrastructureMethods(GlobeController) {
  applyGpsJammingMethods(GlobeController)
  applyCablesMethods(GlobeController)
  applyOutagesMethods(GlobeController)
  applyPowerPlantsMethods(GlobeController)
  applyConflictsMethods(GlobeController)
  applyNotamsMethods(GlobeController)
  applyTrafficMethods(GlobeController)
  applyPipelinesMethods(GlobeController)
  applyRailwaysMethods(GlobeController)
  applyTrainsMethods(GlobeController)
  applyConflictPulseMethods(GlobeController)
  applyChokepointsMethods(GlobeController)
  applyStrikesMethods(GlobeController)
}
