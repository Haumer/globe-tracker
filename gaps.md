# Gaps

## Area Workspace / Area-First Product Gaps

### Backend gaps

- `Workspace` is only a saved camera/layers/filters object. It is not a real area object with geometry, profile, pins, notes, or monitoring behavior.
- Area scope is too weak. The current area snapshot cache is keyed by rounded bbox only, not by a first-class `country`, `theater`, or `polygon` scope.
- `AreaReport` is too thin for an operational area page. It currently summarizes only flights, earthquakes, fires, conflicts, GPS jamming, infrastructure, and anomalies.
- `AreaReport` does not include several of the most valuable layers for an area operating picture:
  - news
  - insights
  - situations / theaters
  - ships
  - trains
  - NOTAMs
  - internet outages / traffic
  - chokepoints
  - webcams
  - military assets
- `Playback` exists, but it is raw playback, not an area-level change engine. It does not answer `what changed here in 1h / 6h / 24h`.
- There is no backend `AreaChangeService` for server-side diffs across layers.
- There is no backend importance-ranking layer for deciding what should be shown first in an area workspace.
- There are no area-specific detail endpoints like:
  - overview
  - changes
  - movement
  - assets
  - replay
- There is no stable `AreaWorkspace` backend primitive with:
  - geometry
  - profile
  - owner / sharing
  - alert preferences
  - pins
  - notes
  - watches
- Some data quality issues are region-specific, which means the backend needs region-aware source strategies instead of one global source for every area.

### Recommended backend primitives

- `AreaWorkspace`
- `AreaScopeResolver`
- `AreaSummaryService`
- `AreaChangeService`
- `AreaArticleCandidateService`
- `MaritimePassageSignalExtractor`

### Product principle

- Keep the frontend thin.
- Backend should scope, rank, aggregate, diff, and cap data.
- Frontend should render a compact area payload and lazy-load detail modules.

## Selective Deep-Read Plan

- Do not run AI across the full news firehose.
- Rank the top `5-10` candidate articles per saved area.
- Hydrate those candidates from article pages even when they did not arrive through RSS.
- Prefer deterministic domain extractors first.
- Use LLMs only for ambiguous articles or conflicting evidence.
- Build briefs from extracted claims plus cited evidence, not raw recent headlines.

### First execution slice

- `AreaArticleCandidateService`
  - merge in-bounds events with named-area matches
  - score by source quality, recency, profile relevance, and state-change terms
  - queue hydration for the highest-value articles that still have weak summaries
- generalized article hydration
  - keep the existing hydration stack
  - remove the effective RSS-only limitation when an article is explicitly selected as an area candidate
- `MaritimePassageSignalExtractor`
  - detect `closed`, `restricted`, `restricted_selective`, `reopening`, `open`
  - detect structured signals like `tolling`, `permission`, `rerouting`, `insurance disruption`
- area brief consumption
  - use extracted article signals to form the assessment
  - always show supporting evidence links

### Cost guardrails

- saved areas only
- no more than `5-10` deep-read candidates per area refresh
- no repeated hydration or analysis for unchanged articles
- no model invocation on articles with already-strong deterministic signals

## Cleanup / Bloat Notes

- `OebbTrainService` looks dead. Train refresh uses `HafasTrainService`, and `OebbTrainService` is only referenced by its own test.
- Tracking intent is split across too many systems: `preferences`, `deeplinks`, `workspaces`, `region mode`, `area report`, `watches`, and `cases`.
- `Workspace` has backend features with no real product surface today: `shared`, `slug`, and `is_default` handling exist, but the UI only supports load / save / delete.
- `WatchesController#index`, `update`, and `destroy` are API-only in practice. The frontend only creates watches.
- `PreferencesController#show` is likely redundant. The app restores preferences from server-rendered JSON on page load and only writes back with `PATCH`.
- `createAreaWatch` exists in the globe controller but has no UI entry point.
- `AreaReport` is useful as a prototype, but it is still a thin one-off summary and overlaps with the future `AreaWorkspace`.
- News ingestion is a complexity hotspot: `NewsRefreshService`, `RssNewsService`, and `MultiNewsService` all run on the poller and converge into one surface.
- The frontend still depends on third-party runtime fetches for core map assets and overlays. Avoid expanding that pattern.

## Freeze / Do Not Extend

- `Workspace` should stay a legacy saved-view system until it is replaced. Do not add pins, notes, alerts, collaboration, or area semantics to it.
- `AreaReport` should not grow into a second tracking product. Use it only as a temporary summary while `AreaWorkspace` is built.
- `Watches` should not get a bigger UI until they are anchored to the future area model. Right now they are a small alerting primitive, not the main tracking object.
- `Region mode` should not gain more product behavior. It is a curated exploration shortcut, not a durable area object.
- The news stack should be frozen at the source-integration level for now. Focus on ranking and area summarization, not additional ingest paths.
- Avoid new browser-side data fetches from third-party sources for core app behavior. Prefer server-owned fetch/cache layers.

## AreaWorkspace Cutover Plan

### Current systems to absorb

- `preferences`
  - keep for pure UI chrome only: sidebar state, right-panel state, open sections
  - move durable spatial state out of it
- `deeplinks`
  - keep for shareable camera/layer state
  - stop treating it as a durable tracking object
- `workspaces`
  - replace with `AreaWorkspace` for saved operating pictures
  - old workspace records can remain as legacy saved views
- `region mode`
  - convert curated regions into starter templates / presets for `AreaWorkspace`
- `area report`
  - retire after `AreaSummaryService` and `AreaWorkspace` overview exist
- `watches`
  - re-anchor as notifications on an `AreaWorkspace`
- `cases`
  - keep, but make them downstream of `AreaWorkspace` instead of a separate starting point

### M1 backend shape

- `AreaWorkspace`
  - `name`
  - `slug`
  - `scope_type` (`country`, `bbox`, `polygon`, `theater`, `preset_region`)
  - `geometry` or normalized bounds
  - `profile`
  - `owner`
  - `alert_preferences`
  - `default_layers`
  - `pinned_objects_count`
- `AreaWorkspacePin`
  - pinned object / node / evidence references
- `AreaWorkspaceNote`
  - lightweight analyst notes
- `AreaScopeResolver`
  - normalize country / theater / bbox / polygon into one internal scope contract
- `AreaSummaryService`
  - ranked operating picture for the initial page load
- `AreaChangeService`
  - `1h / 6h / 24h` diffs for the area

### M1 UI cutover

- Replace the current workspace bar with `Area Workspaces`
- Replace `Area Report` button with `Track Area`
- Keep `Select Region` temporarily, but let it seed a new `AreaWorkspace`
- Land the user on `/areas/:id` instead of rendering the summary inline in the map detail panel

### What stays as-is

- `LayerSnapshotStore`
- `GlobalPollerService`
- ontology/object pages
- playback primitives
- the existing layer APIs as underlying evidence feeds

### What gets retired later

- inline `Area Report` detail panel
- old `Workspace` as the main saved-state concept
- `Create Case` as the first tracking step for areas
