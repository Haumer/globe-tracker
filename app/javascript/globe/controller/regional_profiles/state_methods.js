import { applyRegionalDetailMethods } from "globe/controller/regional_profiles/detail_methods"
import { applyRegionalStateCoreMethods } from "globe/controller/regional_profiles/state_core_methods"

export function applyRegionalStateMethods(GlobeController) {
  applyRegionalStateCoreMethods(GlobeController)
  applyRegionalDetailMethods(GlobeController)
}
