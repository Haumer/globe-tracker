import { applyNewsFeedMethods } from "globe/controller/news_feed"
import { applyNewsRenderingMethods } from "globe/controller/news_rendering"

export function applyNewsMethods(GlobeController) {
  applyNewsRenderingMethods(GlobeController)
  applyNewsFeedMethods(GlobeController)
}
