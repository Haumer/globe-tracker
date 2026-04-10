import { applyRegionalLocalProfileCoverageMethods } from "globe/controller/regional_profiles/local_profile_coverage_methods"
import { applyRegionalLocalProfileShellMethods } from "globe/controller/regional_profiles/local_profile_shell_methods"
import { applyRegionalLocalProfileSummaryMethods } from "globe/controller/regional_profiles/local_profile_summary_methods"

export function applyRegionalLocalProfileMethods(GlobeController) {
  applyRegionalLocalProfileShellMethods(GlobeController)
  applyRegionalLocalProfileSummaryMethods(GlobeController)
  applyRegionalLocalProfileCoverageMethods(GlobeController)
}
