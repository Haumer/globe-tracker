# Globe Tracker — Product Roadmap

## Completed (Frontend Redesign)
- Bottom strip consolidation (active-layer pills, mini-timeline, controls)
- Stats bar cleanup (right-panel toggle, z-index standardization)
- Right panel persistence (reopen bug, empty states, preference storage)
- Sidebar refinement (hidden toggles, active count badges, pulse dots)
- z-index normalization (strict 10–200 hierarchy)
- API Health Monitor admin page (/admin/api_health)

---

## Phase 1: Trust & Reliability

Make existing features reliable before adding new ones. Users must trust the data.

### 1.1 Circuit Breaker
Add circuit breaker to HttpClient concern. When a source fails 3x consecutively, stop calling it for 5 minutes. Prevents hammering dead endpoints and wasting rate limits.
- State machine: CLOSED → 3 failures → OPEN (skip 5min) → HALF-OPEN (try 1) → success → CLOSED
- One concern, ~40 LOC, protects all 30+ services automatically
- Log state transitions for admin visibility

### 1.2 Toast Variants
Currently all toasts look the same. Add visual distinction:
- `_toast("msg", "info")` — current neutral style
- `_toast("msg", "success")` — green left-border
- `_toast("msg", "error")` — red left-border, persists until dismissed
- ~15 LOC CSS + minor JS changes

### 1.3 Loading & Empty States
When a layer activates or right panel tab is empty:
- "Loading flights..." text in right panel while fetching
- "No earthquakes in view" when layer is on but nothing matches viewport
- Subtle loading indicator on quick bar pills during fetch

### 1.4 Health Check Endpoint
Upgrade `/up` with a proper `/health` endpoint that checks:
- Poller running?
- Each data source: last successful poll < 2x expected interval?
- DB connection alive?
- Returns JSON with per-source status for uptime monitors

### 1.5 Stale Data Indicators
Enhance existing freshness dots on quick bar pills:
- Green dot = fresh (<30s)
- Amber dot + "1m" label = warming (30s–2min)
- Red dot + "5m+" label = stale (>2min), dim pill opacity
- "Last updated: Xm ago" in detail panel headers

---

## Phase 2: Cross-Layer Intelligence (The Moat)

Ship the feature that no competitor can match. The value is context, not data.

### 2.1 Intelligence Briefs
Auto-generated periodic summaries — the "daily briefing" for analysts and journalists.
- `IntelligenceBriefService` — runs hourly (or on-demand)
- Pulls from: CrossLayerAnalyzer, AnomalyDetector, TrendingKeywordTracker, AreaReport
- Structured output: CRITICAL / HIGH / NOTABLE / TRENDING sections
- New "Brief" tab in right panel with styled card feed
- "Share Brief" button — copies text summary to clipboard
- Future: daily email digest for Pro users

### 2.2 Insight Chains
Connect isolated insights into causal chains:
- "M5.8 Earthquake → SEA-ME-WE 5 cable at risk → Egypt internet outage +15% → 3 flights rerouted"
- Second pass after CrossLayerAnalyzer.analyze groups insights sharing entities or geographic clusters (<200km)
- UI: chain visualization with arrows between linked insight cards

### 2.3 Temporal Correlation
Add time dimension to cross-layer analysis:
- "GPS jamming started 2h ago, military flights increased 3x since"
- "Fire cluster grew from 5 to 47 hotspots in 6h, now within 50km of nuclear plant"
- Use PositionSnapshot and PollingStats history for delta computation
- Show trend arrows (↑↓→) on insight metrics

---

## Phase 3: Stickiness & Distribution

Make users come back and bring others.

### 3.1 Auto-Suggested Watches
When viewing an insight, offer pre-filled watch creation:
- "Watch this? Alert me if this earthquake triggers an internet outage"
- "Alert me if military flights in Black Sea exceed 10"
- One button → pre-filled watch form from current insight parameters

### 3.2 Shareable Insight Permalinks
Each insight, brief, and area report gets a permalink:
- `/insights/earthquake-infrastructure-2026-03-14-1423`
- Renders static card with map thumbnail (Cesium canvas capture)
- Embeddable in articles, tweets, Slack
- This is the distribution channel — journalists share, OSINT community amplifies

### 3.3 Confirmation Dialogs
Destructive actions need confirmation:
- Workspace delete, watch delete
- Reusable `_confirm("Delete workspace?", callback)` method

### 3.4 Detail Panel Polish
- Scroll indicator when content overflows
- "Last updated" timestamp at bottom of every detail card
- Loading skeleton while /api/connections fetches

### 3.5 Initial Load Performance
Target <3s to interactive:
- Lazy-load non-essential layers (defer satellite TLE parsing)
- Don't fetch railways/power plants until toggled
- Preload terrain tiles for user's last saved camera position
- Compress static data files (country_centroids.js)

---

## Phase 4: Monetization & Growth

### 4.1 Pricing Tiers
- Free: 3 layers, no playback, no alerts
- Pro ($10/mo): all layers, 7-day playback, 5 watches, intelligence briefs
- Analyst ($30/mo): 90-day playback, unlimited watches, daily email briefs, CSV/GeoJSON export

### 4.2 Mobile Strategy
- 2D map fallback (Leaflet/MapLibre) for mobile & low-power devices
- Progressive Web App (PWA) for home screen install
- Push notifications for watch alerts

### 4.3 Community & Content
- Public API for cross-layer insights (free tier)
- Embeddable widgets for news sites
- Weekly "World Situation" email newsletter (auto-generated from briefs)

---

## Competitive Positioning

**Not competing on data depth** — FR24 will always have better flights, MarineTraffic better ships.

**Competing on context** — the insights that only emerge when you see flights + conflicts + weather + infrastructure + natural disasters on the same canvas.

| Competitor | Their strength | Our angle |
|---|---|---|
| FlightRadar24 | Aviation depth | "We show you *why* that flight matters — GPS jamming zone, conflict area, wildfire diversion" |
| MarineTraffic | Maritime depth | "We show you the submarine cable that ship is anchored over" |
| Windy | Weather UX | "We show you what weather is doing to flights, ships, and infrastructure" |
| Liveuamap | Conflict speed | "We show military flights, satellite passes, GPS jamming, and infrastructure damage in context" |
| Palantir | Everything | "Palantir costs $10M/year. We cost $10/month." |
