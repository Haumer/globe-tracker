import { applyUiPanelMethods } from "globe/controller/ui_panel"
import { applyUiPreferenceMethods } from "globe/controller/ui_prefs"
import { applyUiQuickBarMethods } from "globe/controller/ui_quickbar"
import { applyUiMobileMethods } from "globe/controller/ui_mobile"
import { applyUiLayerLibraryMethods } from "globe/controller/ui_layer_library"
import { applyUiStatMethods } from "globe/controller/ui_stats"

export function applyUiMethods(GlobeController) {
  applyUiPanelMethods(GlobeController)
  applyUiQuickBarMethods(GlobeController)
  applyUiLayerLibraryMethods(GlobeController)
  applyUiStatMethods(GlobeController)
  applyUiMobileMethods(GlobeController)
  applyUiPreferenceMethods(GlobeController)
}
