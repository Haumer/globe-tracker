import { applyUiPanelMethods } from "globe/controller/ui/panel"
import { applyUiPreferenceMethods } from "globe/controller/ui/preferences"
import { applyUiQuickBarMethods } from "globe/controller/ui/quickbar"
import { applyUiMobileMethods } from "globe/controller/ui/mobile"
import { applyUiLayerLibraryMethods } from "globe/controller/ui/layer_library"
import { applyUiStatMethods } from "globe/controller/ui/stats"

export function applyUiMethods(GlobeController) {
  applyUiPanelMethods(GlobeController)
  applyUiQuickBarMethods(GlobeController)
  applyUiLayerLibraryMethods(GlobeController)
  applyUiStatMethods(GlobeController)
  applyUiMobileMethods(GlobeController)
  applyUiPreferenceMethods(GlobeController)
}
