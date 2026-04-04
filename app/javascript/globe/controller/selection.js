import { applySelectionAirlineMethods } from "globe/controller/selection_airlines"
import { applySelectionEntityMethods } from "globe/controller/selection_entities"
import { applySelectionSearchMethods } from "globe/controller/selection_search"

export function applySelectionMethods(GlobeController) {
  applySelectionEntityMethods(GlobeController)
  applySelectionSearchMethods(GlobeController)
  applySelectionAirlineMethods(GlobeController)
}
