import { applyNewsFeedMethods } from "./news_feed"
import { applyNewsRenderingMethods } from "./news_rendering"

export function applyNewsMethods(GlobeController) {
  applyNewsRenderingMethods(GlobeController)
  applyNewsFeedMethods(GlobeController)
}
