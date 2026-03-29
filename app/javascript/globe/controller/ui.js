import { applyUiPanelMethods } from "./ui_panel"
import { applyUiPreferenceMethods } from "./ui_prefs"
import { applyUiQuickBarMethods } from "./ui_quickbar"
import { applyUiStatMethods } from "./ui_stats"

export function applyUiMethods(GlobeController) {
  applyUiPanelMethods(GlobeController)
  applyUiQuickBarMethods(GlobeController)
  applyUiStatMethods(GlobeController)
  applyUiPreferenceMethods(GlobeController)
}
