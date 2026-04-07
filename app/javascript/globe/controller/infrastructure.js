import { applyGpsJammingMethods } from "globe/controller/infrastructure/gpsJamming"
import { applyCablesMethods } from "globe/controller/infrastructure/submarineCables"
import { applyPortsMethods } from "globe/controller/infrastructure/ports"
import { applyShippingLanesMethods } from "globe/controller/infrastructure/shippingLanes"
import { applyOutagesMethods } from "globe/controller/infrastructure/internetOutages"
import { applyPowerPlantsMethods } from "globe/controller/infrastructure/powerPlants"
import { applyCommoditySitesMethods } from "globe/controller/infrastructure/commoditySites"
import { applyConflictsMethods } from "globe/controller/infrastructure/conflictEvents"
import { applyNotamsMethods } from "globe/controller/infrastructure/notams"
import { applyTrafficMethods } from "globe/controller/infrastructure/internetTraffic"
import { applyPipelinesMethods } from "globe/controller/infrastructure/pipelines"
import { applyRailwaysMethods } from "globe/controller/infrastructure/railways"
import { applyTrainsMethods } from "globe/controller/infrastructure/trains"
import { applyConflictPulseMethods } from "globe/controller/infrastructure/conflictPulse"
import { applyChokepointsMethods } from "globe/controller/infrastructure/chokepoints"
import { applyStrikesMethods } from "globe/controller/infrastructure/strikes"
import { applyMilitaryBasesMethods } from "globe/controller/infrastructure/militaryBases"
import { applyAirbasesMethods } from "globe/controller/infrastructure/airbases"
import { applyNavalVesselsMethods } from "globe/controller/infrastructure/navalVessels"

export function applyInfrastructureMethods(GlobeController) {
  applyGpsJammingMethods(GlobeController)
  applyCablesMethods(GlobeController)
  applyPortsMethods(GlobeController)
  applyShippingLanesMethods(GlobeController)
  applyOutagesMethods(GlobeController)
  applyPowerPlantsMethods(GlobeController)
  applyCommoditySitesMethods(GlobeController)
  applyConflictsMethods(GlobeController)
  applyNotamsMethods(GlobeController)
  applyTrafficMethods(GlobeController)
  applyPipelinesMethods(GlobeController)
  applyRailwaysMethods(GlobeController)
  applyTrainsMethods(GlobeController)
  applyConflictPulseMethods(GlobeController)
  applyChokepointsMethods(GlobeController)
  applyStrikesMethods(GlobeController)
  applyMilitaryBasesMethods(GlobeController)
  applyAirbasesMethods(GlobeController)
  applyNavalVesselsMethods(GlobeController)
}
