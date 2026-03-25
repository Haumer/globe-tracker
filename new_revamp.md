# GlobeTracker Outstanding Revamp

This file tracks only open work.
Completed architecture and cleanup steps were removed on purpose.

## Working Model

`retrieve -> normalize -> ontology -> relate -> present`

Current focus is the last two steps:

- build stronger typed relationships
- present those relationships as one coherent context instead of separate panes

## Open Product Direction

### 1. Frontend Convergence

The backend now knows more than the UI shows.

Next frontend sequence:

1. add one shared `selected context` state
2. render a single right-panel context view from that state
3. wire `news`, `insights`, and `strategic nodes` into it first
4. make `evidence`, `related nodes`, and `flows/markets` visible in one place
5. only then reduce or retire the older parallel-pane workflow

First implementation slice:

- keep the existing detail panel working
- add a shared context pane in the right panel
- populate it from:
  - story clusters / news leads
  - cross-layer insights
  - chokepoints

Second slice:

- add a node-context API backed by ontology relationships
- let the context pane show durable relation evidence instead of only local payload fields

### 1a. Editorial Leads

The next newsroom-facing product layer should be `leads`, not more raw overlays.

Each lead should answer:

- what happened
- why it matters
- what evidence supports it
- what is exposed downstream
- what is still missing / unverified

First lead families:

- `verification lead`
- `strategic pressure lead`
- `operational disruption lead`

### 1b. Live Observation Surface

Cameras and live streams should feel like real observation nodes, not just another point layer.

Immediate frontend goal:

- rank truly live / fresh feeds above passive webcams
- give live feeds larger preview cards in the right panel
- make freshness and source type obvious
- make map markers distinguish `live now` from `periodic` and `stale`
- use cameras as fast corroboration when nearby stories / insights need visual confirmation

### 2. Global Relationship Builders

Already in place:

- `theater_pressure`
- `flow_dependency`
- `downstream_exposure`
- `operational_activity`
  - ships -> chokepoints / submarine cables
  - flights -> theaters / stressed airports / bases
  - jamming + NOTAM evidence attached where present

Next builders:

1. stronger `local_corroboration`
   - story cluster -> observed event -> infrastructure / camera / traffic evidence
2. `actor_overlap`
   - story actors -> operators / owners / institutions

### 3. Do Not Force

Keep these guardrails:

- do not treat simple map overlap as proof
- do not infer sabotage from a ship merely being nearby
- do not infer price causality from one local incident
- do not pretend a satellite observed an event unless mission/time geometry makes that plausible
- do not treat multi-source publisher pickup as independent confirmation

## Open Data Gaps

These are the clearest missing inputs for stronger global linking:

- ports
- cable landing stations
- ASN / ISP / operator metadata
- normalized organization / operator identities
- satellite observation semantics:
  - sensor type
  - pass / footprint events
  - revisit / plausibility
- first-class strike / kinetic-event modeling if conflict verification is a priority

## Immediate Sequence

1. improve the camera / live-stream surface so the map feels genuinely live
2. shared selected-context pane in the right panel
3. relation-backed node-context API
4. stronger `local_corroboration`
5. source expansion where it improves corroboration quality
