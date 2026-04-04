import { applyUiLayerLibraryMethods } from "./ui_layer_library"
import { applyUiPanelMethods } from "./ui_panel"
import { applyUiPreferenceMethods } from "./ui_prefs"
import { applyUiQuickBarMethods } from "./ui_quickbar"
import { applyUiStatMethods } from "./ui_stats"

export function applyUiMethods(GlobeController) {
  applyUiPanelMethods(GlobeController)
  applyUiLayerLibraryMethods(GlobeController)
  applyUiQuickBarMethods(GlobeController)
  applyUiStatMethods(GlobeController)
  applyUiPreferenceMethods(GlobeController)
}
