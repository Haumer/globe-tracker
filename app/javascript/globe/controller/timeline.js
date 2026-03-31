import { applyTimelineControlMethods } from "globe/controller/timeline_controls"
import { applyTimelineDetailMethods } from "globe/controller/timeline_details"
import { applyTimelineEventMethods } from "globe/controller/timeline_events"
import { applyTimelineFrameMethods } from "globe/controller/timeline_frames"

export function applyTimelineMethods(GlobeController) {
  applyTimelineControlMethods(GlobeController)
  applyTimelineFrameMethods(GlobeController)
  applyTimelineEventMethods(GlobeController)
  applyTimelineDetailMethods(GlobeController)
}
