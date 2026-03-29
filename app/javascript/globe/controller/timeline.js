import { applyTimelineControlMethods } from "./timeline_controls"
import { applyTimelineDetailMethods } from "./timeline_details"
import { applyTimelineEventMethods } from "./timeline_events"
import { applyTimelineFrameMethods } from "./timeline_frames"

export function applyTimelineMethods(GlobeController) {
  applyTimelineControlMethods(GlobeController)
  applyTimelineFrameMethods(GlobeController)
  applyTimelineEventMethods(GlobeController)
  applyTimelineDetailMethods(GlobeController)
}
