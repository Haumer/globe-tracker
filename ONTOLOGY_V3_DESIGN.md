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
| Scorecard harness | this branch |
| `NewsPlaceResolver` + rewire | this branch |
| `Situation` schema + resolver | this branch |
| Backfill existing `place` entities | follow-up |
| Open taxonomy / `general` as mentions | phase 2 |
| Scheduler catch-up (starves ≥12h jobs) | independent, unrelated fix |

## Not addressed here

- The poller fires a schedule only when it ticks inside a 5-second residue
  window, with no persisted last-run and no catch-up, so ≥12h jobs are skipped
  entirely when the process is not up at that instant. This starves the asset
  graph and supply chain, but it is a scheduler bug, not an ontology one.
- Satellites (13,584 rows) and weather alerts (540) have zero ontology presence.
- FIRMS and ACLED lack API keys in dev, so those layers are empty locally.
