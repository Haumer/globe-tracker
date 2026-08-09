// One category palette for the news layer.
//
// This lived in five places -- three in news_feed.js, two in news_rendering.js --
// and they had drifted apart: the live map knew nothing about `cyber`, the
// timeline did, and none of them covered the values the AI enricher actually
// writes. Since enrichment overwrites `category` on most rows, the majority of
// pins were falling through to the grey default.
//
// The keys here are exactly ThreatClassifier::CATEGORY_NAMES. If you add one
// there, add it here; a category with no colour is invisible as a category.
export const NEWS_CATEGORY_COLORS = {
  conflict: "#f44336",
  terror: "#b71c1c",
  disaster: "#ff5722",
  unrest: "#ff9800",
  health: "#e91e63",
  economy: "#ffc107",
  diplomacy: "#4caf50",
  cyber: "#00bcd4",
  politics: "#5c6bc0",
  science: "#26a69a",
  // Deliberately muted. Sport is a large share of the feed and is real news, but
  // it should not read as an alert next to a strike or an outbreak.
  sports: "#8d6e63",
  other: "#90a4ae",
}

export const NEWS_CATEGORY_FALLBACK = NEWS_CATEGORY_COLORS.other

export function newsCategoryColor(category) {
  return NEWS_CATEGORY_COLORS[category] || NEWS_CATEGORY_FALLBACK
}
