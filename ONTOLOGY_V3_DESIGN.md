# Ontology v3 — design

## Why a third attempt

Two prior approaches exist and neither can be scored, because nothing was ever
baselined. Everything below is measured on the dev corpus (2026-08-11).

### The funnel

```
31,454 articles
 →  9,327  survive the scope classifier   (29.7%)  ← drops 70.3%
 →  5,753  produce a claim                (61.7% of in-scope)
 →  2,269  claim is clusterable           (39.4%)  ← drops 60.6% as family `general`
 =  7.2% end-to-end
```

**92.8% of the loss happens before the graph is touched**, in two hand-written
vocabularies: an English-term scope regex, and a 12-family allowlist in
`NewsStoryClusterer::CLUSTERABLE_EVENT_FAMILIES`.

The extractor itself is fine: given in-scope text it produces a claim 61.7% of
the time. `NewsClaimExtractor` is 24 regexes over 79 hardcoded actors — no AI
participates in deciding *what happened*.

### What the graph looks like

| Metric | Today |
|---|---|
| Ingest yield (articles → graph) | 7.2% |
| Events linked to a **non-news** object | **5.7%** |
| Events under a real umbrella (not a continent) | 37.7% |
| Event places that are actually places | ≤15% |
| Asset-graph freshness / supply-chain freshness | 51h / 110d |

Of 17,248 links out of ontology events, 14,668 (85%) point at news actors and
news places. The graph is news talking to itself.

### Two defects behind those numbers

1. **Publisher-as-place.** `NewsStoryClusterer` line 211 resolves location from
   `NewsEvent.name`, which is the publisher. 3,269 of 3,835 `occurred_at`
   relationships (85%) anchor an event to its own newspaper; 354 of 630 `place`
   entities are mastheads. Upstream, 34.1% of news coordinates are derived from
   the publisher (`source_country_hint` 27.2% + `publisher_domain` 6.9%).
   `OntologyV2InfrastructureImpactService` already carries a `publisher_location_name?`
   workaround — a downstream patch for an upstream defect.

2. **No tier above "one story".** The chain is
   `article → claim → cluster → ontology event`. A cluster is one bombing.
   Nothing represents "the Iran war" as an object events belong to. The theater
   concept exists but is a lookup table: `NAMED_THEATERS` (24 literals),
   `SITUATION_NAMES` (6 lat/lng boxes), `THEATER_REGIONS` (8 continents).
   **62.3% of geolocated conflict clusters fall through to a continent or
   "Global"** — the largest single "theater" is *Americas*, which is not a war.

## Principle

> Whenever we get any data we must be able to classify it well enough to connect
> it to other data.

The current design is **match-or-drop**: compare against a closed vocabulary,
discard the misses. Every number above follows from that. v3 is
**extract-then-resolve**: take what the source gives, resolve it against what
already exists, mint a new object when nothing matches.

This is what Palantir's ontology does structurally — object types, link types
and action types are *data*, editable at runtime, with entity resolution as an
explicit named stage rather than an allowlist.

## Components

### 1. `NewsPlaceResolver` — one honest answer to "where"

Single source of truth for the location of a news item. Never reads
`NewsEvent.name`.

- Coordinates first (99.5% coverage), carrying their precision.
- A **place name** only from `geocode_place_name`, and only at trustworthy
  precision tiers (`city`/`place`/`region`/`airport`) — the same gate
  `Api::NewsController::LOCATED_PRECISIONS` already applies for display.
- **Reject publisher-derived bases** outright: `publisher_domain`,
  `source_country_hint`. These describe where the *newsroom* is.
- Fall back to country from `geocode_country_code`, labelled as such.
- Return a struct carrying `name`, `lat`, `lng`, `precision`, `basis`,
  `confidence` so callers can gate rather than guess.

Consumers: `NewsStoryClusterer#build_payload`, `NewsOntologySyncService#sync_place_entity`.
This is a prerequisite for component 2 — a Situation layer built on
publisher-as-place would group stories by which paper ran them.

### 2. `Situation` — the missing tier

A persistent, first-class umbrella that events link to, replacing a string
computed from a bounding box.

- Created when a group of related events has no home, so a *new* conflict gets
  named instead of becoming "Americas".
- Matched on actor overlap, geographic coherence, narrative token overlap and
  time continuity — the same signals the clusterer already computes, applied one
  level up and with much wider windows.
- Carries a lifespan (`first_seen_at`, `last_seen_at`, `status`), so situations
  go dormant instead of being deleted.
- `NAMED_THEATERS` and friends become *seeds* for this table, not the mechanism.

Two pins on the map, one situation — an attack on Tehran and a bombing in
Hormuz are separate events and the same war.

### 3. Open taxonomy (phase 2, not in this branch)

Move `EVENT_RULES`, `ACTOR_DEFINITIONS` and the theater literals from Ruby
constants into tables, and route unrecognised events to `unclassified` with the
raw label retained, plus a promotion step that turns frequent labels into real
types. This is what stops the model re-ossifying — but it is the largest and
riskiest piece, and it is worthless until 1 and 2 land.

Deliberately deferred: the `general` family (60.6% of claims) should become
*mention* edges between actors and places rather than being dropped — linkable
without polluting the map. Needs component 1 first.

### 4. Scorecard — how we will know

Neither prior approach can be compared to this one today. Before changing
behaviour, the branch adds:

- **A frozen corpus**: a contiguous time window, every article, unfiltered.
  Contiguous because the thing under test is *grouping* — random-sampling across
  months separates stories that belong together and destroys the signal.
  Unfiltered because `out_of_scope` is 70.3% of the data and the largest gate;
  excluding it makes recall unmeasurable, which is how the last two attempts
  scored themselves as fine.
- **`rake ontology:score`**: prints the table above for the current code, so any
  change is a diff against a number.

Metrics 1–3 are gameable in isolation — link everything to everything and
connectivity hits 90%. They are only meaningful paired with **anchor precision**,
so the scorecard always reports them together.

## Sequencing

| Step | Status |
|---|---|
| Scorecard harness (`ontology:score`, `ontology:corpus`) | **done** — `757ba6b` |
| `NewsPlaceResolver` + rewire of all three call sites | **done** — `af1fc17` |
| Backfill existing anchors (`ontology:repair_places`) | **done** — `af1fc17`, run on dev |
| `Situation` schema + resolver | **next** |
| Open taxonomy / `general` as mentions | phase 2 |
| Scheduler catch-up (starves ≥12h jobs) | independent, unrelated fix |

### Where the numbers stand

| Metric | Before | After |
|---|---|---|
| Anchor precision | 66.5%¹ | **90.6%** |
| Ingest yield | 7.2% | 7.2% (untouched) |
| Cross-domain link rate | 12.0% | 12.0% (untouched) |
| Situation coverage | 37.4% | 37.4% (untouched) |

¹ The first baseline read 14.7%, measured with a publisher set that folded in
`NewsEvent#name`. That column is mixed — real place names as often as mastheads —
so it flagged legitimate anchors and overstated the defect. 66.5% is the same
population measured with the corrected instrument, but over all events rather
than the 30-day window, so it is indicative rather than exact. **The clean
before/after on an identical window was not captured, because the instrument was
fixed after the baseline was taken.** Re-running `ontology:score` on a machine
that has not had `repair_places` applied would settle it.

The three untouched metrics are the point of the next step: fixing the anchor was
a prerequisite for the Situation layer, not a substitute for it. A Situation
layer built on publisher-as-place would have grouped stories by which paper ran
them.

### Residual known issues

- 9.4% of anchors are still publisher text that reached a city-precision
  geocode. Needs its own look; the gate cannot catch it because the geocoder
  asserted a city.
- `ontology:repair_places` calls a private method via `send`. Acceptable for a
  one-shot repair, but if it becomes a recurring job the resolution path should
  be promoted to a public API on `NewsOntologySyncService`.

## Not addressed here

- The poller fires a schedule only when it ticks inside a 5-second residue
  window, with no persisted last-run and no catch-up, so ≥12h jobs are skipped
  entirely when the process is not up at that instant. This starves the asset
  graph and supply chain, but it is a scheduler bug, not an ontology one.
- Satellites (13,584 rows) and weather alerts (540) have zero ontology presence.
- FIRMS and ACLED lack API keys in dev, so those layers are empty locally.
