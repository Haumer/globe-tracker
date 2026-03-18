# Situation Panel Redesign — Theater-first Hierarchy

## Problem

The right panel currently mixes unrelated stories (Berlin rent protests next to Iran war coverage), shows cross-layer signal chips without context ("3 mil flights" — why does this matter?), crams everything into tiny cards with no expansion, and "Reveal all connected layers" enables 7 global layers causing lag.

## Proposed Structure

### Theater-grouped, expandable situation cards

Replace the flat sorted-by-score list with a grouped hierarchy using the existing `theater` field:

```
SITUATIONS
├─ ▾ Middle East / Iran War
│    Israel-Palestine        92 SURGING
│    Yemen-Houthi            55 ACTIVE
│    Iran Nuclear            71 ACTIVE
│
├─ ▾ Eastern Europe
│    Ukraine War             78 ACTIVE
│
└─ ▸ Sub-Saharan Africa          [+3]   ← collapsed if low scores
```

### Three card states

**1. Collapsed (default)** — one line per situation:
```
Israel-Palestine        92 ▲ SURGING
```

**2. Summary (click to expand)** — adds headline + signal count:
```
Israel-Palestine                    92 SURGING
Israeli airstrikes on Gaza intensify...   Reuters · 2h
[🛩 3] [📡 47%] [🔥 12] [📊 1301]
```

**3. Expanded (click again)** — full detail in-place:
```
✕  ISRAEL-PALESTINE                     92 SURGING
147 reports today · 12 sources · spike 5.8x

─ TOP STORIES ─────────────────────────────────
Israeli airstrikes on Gaza intensify...
  Reuters · 2h ago
Palestinian rocket barrage hits southern...
  BBC · 1h ago
[+32 more]

─ WHY THESE LAYERS MATTER ─────────────────────

🛩 3 military flights
  Aircraft on patrol near active hostilities —
  likely reconnaissance or close air support

📡 47% GPS jamming
  Electronic warfare degrading civilian
  aviation navigation in the region

🔥 12 fire hotspots
  Satellite-detected fires consistent
  with airstrikes or burning infrastructure

📊 1,301 historical incidents
  UCDP conflict database since 2022.
  Provides baseline for current escalation.

[Explore this area →]
```

### "Explore this area" replaces "Reveal all connected layers"

Current behavior: enables 7 global layers → lag, unrelated data everywhere.

New behavior:
1. Fly to the situation's coordinates (reuse existing camera animation)
2. Enable ONLY layers where `cross_layer_signals[key] > 0` for this zone
3. Scope data fetches to the visible viewport (already works this way)
4. Show a "Back to overview" button to restore previous camera + layer state

### News separation

Expanded situation cards show their own `top_articles` inline. The separate News tab continues to exist for browsing all news, but the theater grouping naturally separates "Berlin rent" (no theater) from "Gaza strikes" (Middle East / Iran War theater).

## Implementation Plan

### 1. Backend: Add context strings to cross-layer signals

**File:** `app/services/conflict_pulse_service.rb`

Add a `signal_context` hash alongside `cross_layer_signals`:
```ruby
signal_context: {
  military_flights: "Aircraft on patrol near active hostilities",
  gps_jamming: "Electronic warfare degrading civilian navigation",
  fire_hotspots: "Satellite-detected fires consistent with strikes",
  known_conflict_zone: "Historical conflict events from UCDP database"
}
```

Static strings keyed by signal type. Could be made dynamic later (e.g., AI-generated per zone).

### 2. Frontend: Refactor situation card rendering

**File:** `app/javascript/globe/controller/infrastructure/conflictPulse.js`

**a) Group zones by theater:**
```javascript
const theaters = {}
zones.forEach(z => {
  const t = z.theater || "Other"
  ;(theaters[t] ||= []).push(z)
})
// Sort theaters by max pulse_score descending
// Sort zones within each theater by pulse_score descending
```

**b) Render theater groups with collapsible headers:**
- Theaters with max score < 40: collapsed by default
- Theaters with active/surging zones: expanded by default

**c) Three-state card expansion:**
- Track `_expandedZones` map: `{ cellKey: 'collapsed' | 'summary' | 'expanded' }`
- Click cycles: collapsed → summary → expanded → collapsed
- Only one expanded card at a time (auto-collapse others)

**d) Expanded card renders `signal_context` from backend:**
- Each signal gets icon + count + context string
- Only show signals where count > 0

### 3. Frontend: Scoped layer reveal

**File:** `app/javascript/globe/controller/infrastructure/conflictPulse.js`

Refactor `revealPulseConnections()`:

```javascript
exploreSituation(zone) {
  // Save current state for "Back to overview"
  this._savedCamera = viewer.camera.position.clone()
  this._savedLayers = this._getActiveLayers()

  // Fly to zone
  this._flyTo(zone.lat, zone.lng, 800000)

  // Enable only layers with actual signals
  const signals = zone.cross_layer_signals
  if (signals.military_flights > 0) this._enableLayer('flights')
  if (signals.gps_jamming > 0)      this._enableLayer('gpsJamming')
  if (signals.fire_hotspots > 0)    this._enableLayer('fires')
  if (signals.known_conflict_zone)  this._enableLayer('conflicts')
  // Skip cables, chokepoints, outages unless relevant
}

backToOverview() {
  this._restoreCamera(this._savedCamera)
  this._restoreLayers(this._savedLayers)
}
```

### 4. Right panel tab: rename "Insights" or merge

Consider whether situations should live in:
- A new "Situations" tab (cleanest)
- Replace the current conflict pulse detail panel behavior
- Or stay in the detail panel but with the new grouped rendering

Recommendation: **New "Situations" tab** in the right panel, always visible when conflict pulse data exists. This is where the theater-grouped cards live. The detail panel (bottom-left) stays for individual entity clicks.

## Files to Modify

| File | Change |
|------|--------|
| `app/services/conflict_pulse_service.rb` | Add `signal_context` hash to zone output |
| `app/javascript/globe/controller/infrastructure/conflictPulse.js` | Theater grouping, 3-state cards, scoped explore |
| `app/views/pages/_right_panel.html.erb` | Add Situations tab |
| `app/javascript/globe/controller/situational.js` | Wire up new tab visibility + sync |
| `app/assets/stylesheets/pages/_home_right_panel.scss` | Styles for theater groups, expandable cards |

## Not in Scope

- AI-generated per-zone context strings (use static strings first)
- News tab restructuring (theater grouping in situations handles the mixing problem)
- Mobile layout changes
