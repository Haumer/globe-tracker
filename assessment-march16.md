# Globe Tracker — Assessment (March 16, 2026)

## What We Built
A **real-time global intelligence dashboard** — 30+ live data layers across aviation, maritime, space, seismic, news, conflicts, infrastructure, and cyber, all rendered on a 3D Cesium globe with temporal playback.

## What Works Well

1. **Cross-layer intelligence** — The killer feature. Earthquake → submarine cable → internet outage connections are automatic. No competitor has this.
2. **Breadth** — 30+ layers, 100+ RSS feeds, 39 services, 26 Sidekiq jobs. Unmatched coverage at consumer pricing.
3. **Temporal playback** — 7-day timeline with position interpolation for flights/ships/satellites. Most tools are stuck in "now."
4. **Clean architecture** — Thin controllers, heavy services, modular Stimulus JS (36 modules), concerns for reuse (Refreshable, HttpClient with circuit breaker).
5. **Shareability** — Deep links encode full state. Workspaces for named views. No login required to view.
6. **Conflict theater system** — Hex grid, strike arcs, theater grouping, ripple animation, breadcrumb connections.
7. **Admin instrumentation** — Per-source health dashboard with latency, success rate, error trends.

## What Doesn't Work Well

1. **Zero test coverage** — 20K+ LOC, zero tests. Any refactor risks silent breakage. #1 technical risk.
2. **No data freshness indicators** — Users can't tell if data is 10 seconds or 30 minutes old. Erodes trust.
3. **News quality** — Geocoding rough, dedup catches ~80%, no curation. Layer feels noisy.
4. **Mobile experience** — 30+ toggles overwhelming on small screens. No PWA.
5. **Poll-based, not event-driven** — 30-second latency for breaking events.
6. **Hex click UX** — Click priority fixed but still unintuitive.
7. **Reported bugs** — Satellite connections duplicates, GPS jamming toggle, weather sat/war linkage.

## Architecture

```
Frontend (Stimulus + Cesium, 36 modules, ~10K LOC)
  → Polling: 10s flights, 60s secondary
  ↓
Rails API Controllers (34 endpoints)
  → Viewport-aware queries, Redis cache (2-5 min)
  ↓
Sidekiq Workers (26 jobs)
  → GlobalPollerService scheduler (enqueue only, zero DB/HTTP)
  ↓
External APIs (30+ sources)
  → Circuit breaker + retry, fallback to cache
  ↓
PostgreSQL (18 models, 40+ indexes)
```

## Recommended Next Steps

| Priority | Action | Impact |
|----------|--------|--------|
| 1 | Add test framework (critical service tests) | Prevents regressions |
| 2 | Freshness indicators (green/amber/red dots) | Trust |
| 3 | News dedup UI ("4 sources" badges) | Quality |
| 4 | Fix reported bugs (sat connections, GPS jamming) | Polish |
| 5 | Mobile optimization / PWA | Reach |
| 6 | Real-time push via ActionCable | Latency |
| 7 | LLM-generated intelligence briefs | Narrative |

## Ratings

| Aspect | Rating |
|--------|--------|
| Concept | A+ |
| Breadth | A |
| Architecture | A- |
| Frontend | A- |
| Data Quality | B+ |
| Testing | F |
| Performance | B |
| UX | B- |
| Reliability | B+ |
