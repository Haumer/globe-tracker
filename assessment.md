# Globe Tracker — Full Analysis (2026-03-15)

## What We Do Well

### 1. Cross-Layer Intelligence (Our Killer Feature)
No competitor connects earthquake → submarine cable → power plant → flight disruption on the same canvas. The `CrossLayerAnalyzer`, `ConnectionFinder`, and `ConvergenceDetector` are genuinely unique. This is the moat.

### 2. Architecture
- Clean separation: thin models → service-heavy business logic → thin API controllers → modular Stimulus JS
- Background polling via `GlobalPollerService` keeps all data fresh without blocking requests
- `HttpClient` concern with circuit breaker + retry + cache fallback is production-grade
- Viewport-aware fetching saves massive bandwidth

### 3. Breadth
30+ live layers, 39 services, 42 API endpoints. Flights, ships, satellites (24 categories with SGP4), trains, earthquakes, fires, conflicts, news (100+ RSS feeds + 7 APIs), weather, GPS jamming, internet outages/traffic, NOTAMs, webcams, submarine cables, pipelines, power plants, railways, commodities. Nobody else has this on one canvas.

### 4. Temporal Dimension
7-day timeline playback with position interpolation, TLE snapshots for satellite replay, and event recording across all layers. This turns a real-time dashboard into an analytical tool.

### 5. Shareability
Deep links encode full state (camera, layers, filters, selections) in URL hash. Workspaces for saved views. No login required for viewing.

---

## What's Done Poorly

### 1. Testing — Critical Gap
~11 test files vs 20K+ LOC. Zero JS tests. Any refactor could silently break layers. Single biggest technical risk.

### 2. No Data Freshness Indicators
Users can't tell if earthquake data is 30 seconds or 30 minutes old. Stale data looks identical to fresh. Erodes trust — the most important thing for an intelligence tool.

### 3. Depth vs Breadth Tradeoff
Every layer is "good enough" but none is best-in-class. Flights lack MLAT, ships lack voyage data, satellites lack RCS/radar cross-section. Users who care deeply about one domain will leave for the specialist.

### 4. News Quality
100+ RSS feeds is impressive quantity, but geocoding is rough (country-centroid-level), dedup catches ~80% but misses edge cases, and there's no editorial curation. News layer feels noisy.

### 5. No Real-Time Push
ActionCable is wired up but barely used. Everything is poll-based (10-30 second intervals). For breaking events (earthquake, military escalation), 30 seconds feels slow.

### 6. Mobile Experience
Bottom-sheet sidebar is a start, but 30+ layer toggles in a mobile panel is overwhelming. No native app. PWA not yet implemented.

### 7. No Offline/Degraded Mode
If the network drops, everything stops. No service worker, no cached tile fallback, no "last known state" persistence.

---

## Where to Improve (Highest Impact)

### 1. Make Cross-Layer Insights the Hero
Insights are buried in a tab. They should be front-and-center — a persistent intelligence feed that surfaces automatically when something interesting happens. Think: "3 military flights entered GPS jamming zone near Kaliningrad" appearing as a push notification + map highlight without the user needing to toggle anything.

### 2. Stale Data Indicators
Add a colored dot (green/amber/red) per layer in the sidebar showing data age. Cheap to build (fetched_at exists everywhere) and dramatically increases trust.

### 3. Narrative Intelligence
The raw data is there. What's missing is the "so what?" layer. Auto-generated briefs like: "Unusual: 4 military flights circling Black Sea while GPS jamming detected in eastern Turkey. Last time this pattern occurred: 2025-11-14." LLM integration for narrative generation, not data fetching.

### 4. Alert Channels
Watches exist but only notify in-app. Add email/webhook/Telegram delivery. Power users want "alert me if military flights enter this polygon" and get pinged on their phone.

### 5. Curated Views / Presets
New users see a blank globe and 30+ toggles. Add presets: "Ukraine Conflict Monitor", "Pacific Maritime Watch", "European Aviation", "Global Earthquake Watch". One click loads layers, camera, and filters.

### 6. Per-Layer Depth on Demand
Don't try to beat FlightRadar24 on flights globally. When a user clicks a flight, show everything — route history, airport weather, NOTAMs along the route, nearby GPS jamming, conflicts near destination. Depth comes from cross-referencing.

---

## Competitive Positioning

**"Context, not just data."**

| Competitor | What they do | What we do differently |
|---|---|---|
| FlightRadar24 | Best flight tracking | We show why that flight diverted (conflict zone, GPS jamming, weather) |
| MarineTraffic | Best ship tracking | We show that ship's route crosses a damaged submarine cable |
| GDACS/ReliefWeb | Best disaster monitoring | We show which infrastructure is threatened and who's affected |
| Palantir/Maxar | Enterprise intelligence | We're $10/month, not $10M/year, available in a browser |

### Three Things Nobody Else Does

1. **Automated cross-domain correlation** — "This earthquake's epicenter is 12km from a submarine cable landing point that serves 3 countries currently showing internet outages" — generated automatically, no analyst needed.

2. **Temporal replay across all layers simultaneously** — Rewind 3 days and watch flights + conflicts + weather + earthquakes play back together. No single-domain tool does multi-layer replay.

3. **Instant shareability** — Copy a URL that encodes exactly what you see (camera angle, active layers, selected entities). Send it to a colleague. They see the same thing. No account needed.

### The Gap to Exploit
Specialist tools (FR24, MarineTraffic) will never add cross-domain correlation — outside their business model. Enterprise tools (Palantir) will never be $10/month. We sit in the middle — intelligence-grade correlation at consumer-grade pricing.
