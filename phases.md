# Globe Tracker — Product Strategy

## Core Thesis

Globe Tracker's moat is **cross-domain correlation on a single surface**. No one else combines aviation + maritime + space + infrastructure + security + news on one globe. The strategy is to stop being a visualization tool and become a **monitoring & analysis platform** — where users define what they care about and the system watches for them.

---

## Competitive Landscape

### World Monitor (github.com/koala73/worldmonitor) — 36.5k stars

**What they are:** A news-first intelligence dashboard that added a map. TypeScript/Vite, Globe.gl + Deck.gl, 60+ Vercel Edge Functions, 435+ RSS feeds, 5 dashboard variants (geopolitics, tech, finance, commodity, positive news), Tauri desktop app, 21 languages, AI-powered briefs via LLM pipeline.

**Where they win:**
- AI synthesis — LLM briefs, threat classification, local RAG with browser-side vectors
- Financial data — stock exchanges, central banks, commodities, prediction markets
- Computed intelligence — Country Instability Index, hotspot escalation scoring, geographic convergence
- Content volume — 435+ RSS feeds, 26 Telegram OSINT channels, live news streams
- Platform maturity — 554 tests, proto-first APIs, command palette, desktop app, PWA offline

**Where we win:**
- 3D globe fidelity — Cesium with real terrain, photorealistic 3D buildings, atmospheric effects (Globe.gl is visually simpler)
- Satellite intelligence — Orbital propagation via satellite.js, TLE tracking, classified satellite identification via orbital mechanics analysis. They don't do this.
- Flight tracking depth — Dead reckoning, merged OpenSky+ADSB sources, squawk/emergency detection, full telemetry (IAS, TAS, Mach, wind, OAT, signal strength)
- Maritime depth — Real-time AIS WebSocket stream with full vessel data vs. likely cached positions
- Historical playback — Snapshot recording with intelligent dedup thresholds + timeline scrubber for replaying positions
- GPS jamming computation — Self-computed from ADS-B NACp values, not consuming someone else's feed
- Spatial analysis tools — Circle selection, country filtering, overhead satellite queries, correlation potential

**Strategic takeaway:** Don't compete on news/AI/finance. Double down on spatial intelligence, tracking fidelity, and the "analyst's globe" positioning. They're a dashboard with a map; we're a globe with intelligence.

---

## Target Users (Ordered by Priority)

### 1. OSINT Enthusiasts & Citizen Analysts (start here)
- Follow military aviation, conflict zones, GPS jamming, satellite passes
- Active on Twitter/X, Reddit (r/OSINT, r/ADSB, r/flightradar24)
- Will tolerate rough edges for unique capability
- Viral potential — shareable discoveries drive organic growth
- Monetization: freemium (free basic, paid for alerts + saved views + history)

### 2. Journalists & Researchers (phase 2)
- Need to monitor regions, verify events, correlate data
- Will pay for reliability and export/embed features
- Smaller audience but higher willingness to pay

### 3. Security Operations / Infrastructure Monitoring (phase 3)
- Requires enterprise features (SSO, SLAs, audit logs)
- Requires uptime guarantees — defer until product-market fit is proven

---

## Phase 1 — Make It Sticky (Weeks 1-3)

Goal: Give users a reason to come back tomorrow. Right now every session starts from zero.

### 1.1 Saved Views (Workspaces)

New model: `Workspace`
```
- user_id
- name ("MENA Aviation Watch", "European GPS Jamming")
- camera (lat, lng, height, heading, pitch)
- layers (JSONB — which layers are on, with per-layer config)
- filters (JSONB — countries, altitude ranges, entity types)
- is_default (boolean)
- shared (boolean — public URL)
```

UI: Dropdown in sidebar header. "Save current view" button. Load/delete/rename. One workspace can be set as default (loads on login).

**This is the single highest-ROI feature. It transforms the app from a demo into a personal tool.**

### 1.2 Shareable Deep Links

Encode view state in URL params:
```
/globe?lat=33.5&lng=36.3&h=500000&layers=flights,gps_jamming&mil=1
```

When someone discovers something interesting, they can share the exact view. This is the viral loop.

### 1.3 Onboarding & Default Scenarios

For logged-out / first-time users, show a quick-start overlay:
- 3-4 preset scenarios as cards: "Live Aviation", "Global Events", "Space Watch", "Infrastructure"
- Clicking one activates relevant layers + flies camera to an interesting region
- Dismissible, doesn't show again after first interaction

### 1.4 Data Freshness Indicators

Add a colored dot to each quick-layer button:
- Green: updated < 30s ago
- Yellow: updated 30s-2min ago
- Red: stale > 2min or errored
- Gray: layer off

Builds trust and tells users when something is wrong without needing admin access.

---

## Phase 2 — Make It Useful (Weeks 4-7)

Goal: Let users extract actionable insight, not just observe.

### 2.1 Watchlists & Alerts

New model: `Watch`
```
- user_id
- name
- watch_type (entity, area, event)
- conditions (JSONB):
  - entity watches: { entity_type: "flight", identifier: "FORTE*", match: "callsign_glob" }
  - area watches: { bounds: [lat,lng,lat,lng], entity_types: ["flight"], filters: { military: true } }
  - event watches: { event_type: "earthquake", min_magnitude: 5.0, region: "JP" }
- notify_via (in_app, email)
- active (boolean)
- last_triggered_at
- cooldown_minutes (default 15)
```

New model: `Alert`
```
- watch_id
- user_id
- title
- details (JSONB)
- entity_type, entity_id
- lat, lng
- seen (boolean)
- created_at
```

UI: Bell icon in stats bar with unread count. Alert feed panel. "Watch this" button on any entity or area selection. Start with in-app notifications only, polled every 10s.

### 2.2 Unified Right Panel

Replace competing entity-list / threats / news / camera panels with a single tabbed container:

- **Details**: Entity detail + selection tray
- **Feed**: News + events + conflicts relevant to current view/selection
- **Alerts**: Triggered alerts, newest first

Panel shows contextually relevant content. Select a country → Feed auto-filters to that country.

### 2.3 Basic Correlation Engine

When viewing an entity or area, surface related data from other layers:

- Flight near conflict zone → show nearby conflict events
- Earthquake → show nearby infrastructure (power plants, cables)
- GPS jamming → show affected flights in the area
- Military flight → show overhead satellites that could observe it

A `CorrelationService` takes (lat, lng, radius, entity_type) and queries across models. Results appear in Detail panel as a "Related" section.

**This is the feature that justifies having all data on one platform.**

### 2.4 Event Timeline Improvements

- Show recent significant events as dots on a persistent mini-timeline at the bottom
- Color-coded by type (red = earthquake, orange = conflict, blue = flight incident)
- Click a dot to fly to the event and show details
- Gives users a "what happened recently" narrative without toggling anything

---

## Phase 3 — Make It Viral & Sustainable (Weeks 8-12)

Goal: Growth mechanics and revenue path.

### 3.1 Public Workspace Sharing

Let users publish workspaces as public pages:
```
globe-tracker.app/w/mena-aviation-watch
```

Read-only, shows the creator's workspace with live data. Embeddable via iframe. Every shared workspace is a landing page.

### 3.2 Export & Embed

- Screenshot with metadata overlay (timestamp, coordinates, active layers)
- Export visible entities as CSV/GeoJSON
- Timelapse recording (automated timelapse of a workspace over N hours)
- Embeddable widget: `<iframe src="globe-tracker.app/embed/w/123">`

### 3.3 Freemium Model

| Feature | Free | Pro ($8/mo) |
|---------|------|-------------|
| All layers | Yes | Yes |
| Saved workspaces | 2 | Unlimited |
| Watchlists | 1 | 20 |
| Alerts | In-app only | In-app + email |
| History playback | 1 hour | 24 hours |
| Export | Screenshot | CSV + GeoJSON + Timelapse |
| Public workspaces | No | Yes |
| API access | No | Yes |

### 3.4 Community Features

- Public feed of interesting discoveries (opt-in)
- "Trending" — auto-detect unusual patterns (spike in military flights, major earthquake, GPS jamming event) and surface as global notification
- Creates a reason to check the app even when not actively monitoring

---

## Technical Priorities (Impact-to-Effort)

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| 1 | Saved workspaces | Medium | Very High |
| 2 | Shareable deep links | Low | High |
| 3 | Data freshness dots | Low | Medium |
| 4 | Onboarding presets | Low | High |
| 5 | Unified right panel | Medium | High |
| 6 | Watchlists + alerts (in-app) | Medium | Very High |
| 7 | Basic correlation | Medium | High |
| 8 | Public workspace sharing | Low | High |
| 9 | Export (CSV/GeoJSON) | Low | Medium |
| 10 | Freemium gating | Medium | Revenue |

---

## What NOT to Build

- Don't add more data sources. 25 is enough — the problem isn't breadth, it's depth.
- Don't build a mobile app. Responsive web is sufficient.
- Don't build real-time collaboration. Sharing is enough.
- Don't build enterprise features (SSO, RBAC, audit logs). Too early.
- Don't over-invest in the admin dashboard. It's internal tooling.

---

## Phase 4 — Make It Smart (Analysis & Intelligence)

Goal: Surface insights automatically, give users analysis tools beyond observation.

### 4.1 Anomaly Detection ✅
Auto-detect unusual patterns: military flight spikes (>3x regional average), new GPS jamming zones, emergency squawk codes, significant earthquakes. Surfaced as diamonds on the mini-timeline with warning indicator.

### 4.2 Entity History (deferred)
Click a flight/ship → see its 24h track from stored position snapshots. "Where has this been?"

### 4.3 Area Reports
Select a country or circle → generate a summary: flights (military count), earthquakes, conflict events, jamming activity, infrastructure at risk. Uses ConnectionFinder + AnomalyDetector. Rendered in the detail panel.

### 4.4 Saved Searches & Filters
Persistent filter presets: "Show me only military flights above FL350 in the Mediterranean." Reusable across sessions.

### 4.5 Notification Channels
Push alerts beyond in-app: email digests, webhook/Slack integration for watches.

---

## Success Metrics

1. **Retention**: Users create workspaces and return within 48 hours
2. **Sharing**: Deep links shared on social media / forums
3. **Watchlists**: Users create watches — they trust the platform to monitor for them
4. **Session depth**: Average session > 5 minutes
