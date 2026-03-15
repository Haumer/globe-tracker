# Globe Tracker — Improvements Roadmap

## Done
- ~~Weather Layer~~ — wind/precip/storms/temp overlay
- ~~Persist Cameras to DB~~ — cameras table with search/filter
- ~~API Rate Limiting~~ — Rack::Attack + Cloudflare
- ~~Push Notifications~~ — ActionCable alerts channel
- ~~ShakeMap / Impact Radius~~ — MMI attenuation rings + infrastructure impact
- ~~Historical Depth~~ — position snapshots, 7-day timeline playback
- ~~Satellite Pass Predictions~~ — SGP4 from observer location
- ~~Financial / Market Data~~ — commodity prices, sanctions tracking
- ~~Cross-Layer Analytics~~ — earthquake→cable→plant, GPS jamming→flights, fire→infrastructure

## Remaining

### Priority 1: Tests + CI/CD
Zero test coverage across 39 services, 28 controllers, 11K lines of JS. Need:
- Service unit tests (WatchEvaluator, SnapshotRecorder, ThreatClassifier, MilitaryClassifier)
- Controller integration tests for API endpoints
- JS tests for critical paths
- GitHub Actions CI pipeline

### Priority 2: News Pipeline Intelligence
- Story clustering (group duplicate coverage across sources)
- Event correlation (link news to map entities — earthquakes, conflicts, fires)
- Source coverage visualization (regional bias detection)
- See plan in phases.md or active Claude plan for details

### Priority 3: Circuit Breakers
Add circuit breaker to HttpClient concern. When a source fails 3x consecutively, stop calling it for 5 minutes.

### Priority 4: Error Handling & Resilience
- Graceful degradation — show cached data with "stale" badge when API fails
- Retry logic with exponential backoff
- Per-layer "last updated" indicators
