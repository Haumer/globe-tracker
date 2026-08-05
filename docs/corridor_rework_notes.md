# Corridor Rework Notes

Date: 2026-04-10

## Why This Needs A Rework

The current chokepoint layer is not serious corridor monitoring.

- Backend model: centerpoint + `radius_km` + nearby ship count + nearby conflict/news.
- Frontend model: render an ellipse around the centerpoint.
- Result: we treat strategic corridors like circular map annotations instead of real operating lanes.

Files:

- `app/services/chokepoint_monitor_service.rb`
- `app/javascript/globe/controller/infrastructure/chokepoints.js`

## What We Found In Production

### 1. The current monitored radii are mostly wrong

Using the current chokepoint radii on production snapshots:

- Hormuz: `0` current ships, `0` 24h snapshots in the monitored radius
- Suez: `0` current ships, `0` 24h snapshots in the monitored radius
- Bab el-Mandeb: `0` current ships, `0` 24h snapshots in the monitored radius
- Malacca: `0` current ships, `0` 24h snapshots in the monitored radius
- Panama: small non-zero counts only

That means the present geometry is not aligned with where the traffic actually appears in our data.

### 2. The AIS history exists for some corridors, but not in the current shape

Broader 24h or 72h regional checks show usable activity around:

- Hormuz: `20` distinct ships over 24h in a broader regional box
- Suez: `42`
- Malacca: `855`

So for those corridors the main issue is not "no ship data." The issue is that we are not modeling the corridor correctly.

### 3. Hormuz has an additional data-quality problem

For Hormuz specifically, recent production snapshots are heavily concentrated west of about `55.4E`, with almost nothing on the Oman/throat side.

That means Hormuz currently has two separate problems:

1. wrong monitored shape
2. asymmetric or weak retained AIS coverage near and east of the throat

This is why the app cannot currently claim serious Hormuz transit counts.

## Product Direction

Replace `chokepoints` with a corridor-state model.

The core object should be a corridor, not a point.

Each corridor should have:

- profile: what it is and why it matters
- geometry: entry gate, throat, exit gate, monitored area polygon
- observations: current traffic and signal facts
- baseline: 24h / 7d / 30d comparison
- state: normal / stressed / constrained / disrupted / closed / recovering
- consequences: route, energy, logistics, market, military

## Data Model Changes

### 1. Add corridor geometry

For each corridor define:

- `monitor_polygon`
- `entry_gate`
- `exit_gate`
- `throat_polygon`
- optional `approach_polygons`

For map rendering, the corridor should be a shaded region, not a circle.

### 2. Add transit detection

Use `position_snapshots` to derive actual ship movement through a corridor.

New derived tables:

- `corridor_transits`
- `corridor_hourly_metrics`

Suggested `corridor_transits` fields:

- `corridor_key`
- `ship_mmsi`
- `entered_at`
- `exited_at`
- `direction`
- `transit_time_minutes`
- `ship_type`
- `destination`
- `confidence`
- `evidence`

Suggested `corridor_hourly_metrics` fields:

- `corridor_key`
- `bucket_start`
- `entries`
- `exits`
- `completed_transits`
- `tankers`
- `cargo`
- `median_transit_time`
- `median_speed`
- `loitering_count`
- `coverage_score`

### 3. Keep long-lived summaries

`position_snapshots` are retained only for a short period. That is fine for playback and recent detection, but not enough for stable baselines.

So:

- keep raw snapshots short-lived
- keep transit records and hourly corridor metrics longer

## Detection Logic

Do not use "ships nearby" as the core metric.

Use:

- gate crossings
- completed crossings
- westbound vs eastbound counts
- dwell inside throat
- median transit time
- speed and heading distributions
- route degradation vs baseline
- observed vs inferred coverage quality

## UI Changes

Replace the ellipse with:

- shaded corridor polygon
- darker throat region
- optional gate lines
- state color by confidence

The corridor card should answer:

1. What is the current state?
2. What changed vs baseline?
3. What evidence supports that?
4. Who is exposed?
5. What should we watch next?

## Build Order

1. Start with Hormuz, Suez, and Malacca
2. Define curated corridor geometry
3. Derive transit events from ship snapshots
4. Build hourly corridor metrics and baselines
5. Replace `ships_nearby` with transit- and state-based outputs
6. Render shaded corridor regions on the map
7. Add a coverage score so weak-feed corridors do not pretend to be well observed

## Hormuz-Specific Read Right Now

The app does not currently have a defensible direct Hormuz transit count.

- The current chokepoint radius misses the corridor
- The retained AIS history is thin or asymmetric east of the throat
- A "current ship count near Hormuz" in this system is not the same thing as a true transit count

So Hormuz should be treated as:

- a priority corridor for geometry rework
- a priority corridor for transit derivation
- a priority corridor for AIS coverage diagnostics
