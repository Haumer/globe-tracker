import { applySituationalCameraMethods } from "./situational_cameras"
import { applySituationalEventMethods } from "./situational_events"
import { applySituationalRightPanelMethods } from "./situational_right_panel"

export function applySituationalMethods(GlobeController) {
  applySituationalEventMethods(GlobeController)
  applySituationalCameraMethods(GlobeController)
  applySituationalRightPanelMethods(GlobeController)
}
