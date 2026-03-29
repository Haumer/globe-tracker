import { applySelectionAirlineMethods } from "./selection_airlines"
import { applySelectionEntityMethods } from "./selection_entities"
import { applySelectionSearchMethods } from "./selection_search"

export function applySelectionMethods(GlobeController) {
  applySelectionEntityMethods(GlobeController)
  applySelectionSearchMethods(GlobeController)
  applySelectionAirlineMethods(GlobeController)
}
