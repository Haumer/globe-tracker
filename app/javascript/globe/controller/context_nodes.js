import { applyContextNodeBuilderMethods } from "globe/controller/context_nodes/builders"
import { applyContextNodeCasePayloadMethods } from "globe/controller/context_nodes/case_payloads"
import { applyContextNodeSelectionMethods } from "globe/controller/context_nodes/selection"
import { applyContextNodeTheaterDossierMethods } from "globe/controller/context_nodes/theater_dossier"

export function applyContextNodeMethods(GlobeController) {
  applyContextNodeCasePayloadMethods(GlobeController)
  applyContextNodeSelectionMethods(GlobeController)
  applyContextNodeTheaterDossierMethods(GlobeController)
  applyContextNodeBuilderMethods(GlobeController)
}
