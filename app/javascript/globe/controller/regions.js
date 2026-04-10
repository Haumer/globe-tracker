// ── Region Mode ──────────────────────────────────────────────
// Focused regional analysis with curated layer profiles.
// Composition entrypoint for regional state, navigation, local-profile UI,
// and map/data overlays.

import { applyRegionalLocalProfileMethods } from "globe/controller/regional_profiles/local_profile_methods"
import { applyRegionalMapMethods } from "globe/controller/regional_profiles/map_methods"
import { applyRegionalNavigationMethods } from "globe/controller/regional_profiles/navigation_methods"
import { applyRegionalStateMethods } from "globe/controller/regional_profiles/state_methods"

export function applyRegionMethods(GlobeController) {
  applyRegionalStateMethods(GlobeController)
  applyRegionalNavigationMethods(GlobeController)
  applyRegionalLocalProfileMethods(GlobeController)
  applyRegionalMapMethods(GlobeController)
}
