import { applySituationalCameraMethods } from "globe/controller/situational_cameras"
import { applySituationalEventMethods } from "globe/controller/situational_events"
import { applySituationalRightPanelMethods } from "globe/controller/situational_right_panel"

export function applySituationalMethods(GlobeController) {
  applySituationalEventMethods(GlobeController)
  applySituationalCameraMethods(GlobeController)
  applySituationalRightPanelMethods(GlobeController)
}
