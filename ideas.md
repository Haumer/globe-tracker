# Ideas

## Split News Into Its Own API Contract

Recommendation: split the news domain logically, but do not extract it into a separate deployed service yet.

Why:
- The news pipeline is already its own domain: ingest, normalize, geocode/project, claim extraction, actor linking, and story clustering.
- The rest of the app still reads those tables directly for conflict pulse, cross-layer analysis, briefs, and the globe feed, so a hard service split now would add operational complexity before delivering much product value.

Suggested path:
1. Define a versioned internal news API contract inside the monolith.
2. Expose first-class resources for `articles`, `claims`, `actors`, `clusters`, and `sources`.
3. Move app consumers behind a dedicated read model or service layer instead of direct table access.
4. Keep the same database and workers initially.
5. Revisit a true service extraction only when another app needs the same API, news needs separate scaling/deploy cadence, or the pipeline is materially slowing the main app.

Current modeling gap:
- The canonical `article` record is still relatively thin. We mostly store `title` and `summary`, plus derived claim/cluster structure. We do not yet have a richer body/authors/media model that would make a standalone news service especially strong on its own.
