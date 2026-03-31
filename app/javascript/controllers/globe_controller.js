import { Controller } from "@hotwired/stimulus"
import { GLOBE_TARGETS, GLOBE_VALUES, NEWS_REGIONS } from "globe/controller/config"
import { applyGlobeControllerMixins } from "globe/controller/mixins"

class GlobeController extends Controller {
  static values = GLOBE_VALUES
  static targets = GLOBE_TARGETS
}

GlobeController.NEWS_REGIONS = NEWS_REGIONS

applyGlobeControllerMixins(GlobeController)

export default GlobeController
