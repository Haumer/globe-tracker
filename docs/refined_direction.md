# Refined Direction

## Product Thesis

Globe Tracker should not be a map with many layers. It should be a system that explains how live events change the importance, state, and consequences of strategic places, assets, and routes.

The product is not:

- a feed reader on a globe
- a collection of overlays
- a proximity engine that says one thing is near another

The product is:

- strategic context
- live signal correlation
- explicit impact chains
- case-building for what matters now

## Core Data Model

We should think about the data in three product buckets, not just static vs dynamic.

### 1. Strategic Assets And Dependencies

These are slow-changing and define why the world matters before anything happens.

- chokepoints
- ports
- airports
- power plants
- pipelines
- cables
- military bases
- factories, refineries, LNG terminals, commodity sites
- country and sector dependencies

Each one needs a permanent strategic profile:

- what it is
- why it matters
- what flows through it
- what depends on it
- what can substitute for it
- what failure or disruption would affect

### 2. Live Signals

These change quickly and should mostly serve as evidence.

- news
- flights
- ships
- strikes
- geoconfirmed events
- jamming
- outages
- fires
- earthquakes
- market and commodity moves

These should not be a destination by default. They should illuminate state changes in the strategic layer.

### 3. Impact And State Change

This is the missing center of the product.

We need to explicitly model:

- normal
- threatened
- degraded
- disrupted
- offline
- recovering

And we need to explain:

- what changed
- what evidence supports it
- what downstream effects are already visible
- what next-order effects are likely
- what would confirm or disconfirm the current read

## Core Operating Logic

The app should reason in chains like this:

1. Strategic asset or route exists and has a baseline profile.
2. A live event or signal changes its risk or operating state.
3. That state change alters movement, trade, energy, market, or military behavior.
4. The system records observed, inferred, and projected consequences separately.
5. A case opens when the chain becomes materially important.

Examples:

- conflict near Hormuz -> shipping risk rises -> traffic pattern changes or reroutes -> energy and freight pressure -> negotiation or coercion signals
- strike near an airport -> airport status shifts -> flight disruption pattern changes -> military or civilian access changes
- earthquake near infrastructure -> asset damage risk rises -> outages or operational disruption -> downstream supply or price effects

## What Production Data Supports Best Right Now

The live database is strongest in:

- flights
- ships
- fire hotspots
- earthquakes
- outages and internet traffic
- jamming
- news
- commodity prices
- basic supply-chain exposure and dependency tables

That means the best near-term wedge is:

conflict or disaster -> strategic asset or route -> movement change -> commodity or market consequence

## What To Stop Doing

- stop treating news volume as insight
- stop presenting proximity as analysis
- stop adding generic layers that do not change an assessment
- stop letting the right panel mirror system categories instead of user questions
- stop relying on polished prose to hide weak state models

## Derived Layer Direction

### Keep But Reshape

- `conflict_pulse`
- `cross_layer_analyzer`
- `supply_chain_lens`
- `pipeline_market_context`
- `theater_brief` as a secondary narrative layer

These should become stricter about:

- observed vs inferred vs projected
- baseline comparison
- explicit evidence chains
- asset and route state transitions

### Rebuild

- `chokepoint_monitor`
- `area_impact_assessment`

These currently overuse heuristics, thresholds, and narrative summaries. They need a more explicit consequence model.

## UX Direction

### Globe

The globe is for orientation and spatial comparison.

It should answer:

- what is this
- where is it
- why does it matter now

### Context Rail

The rail should be thin and opinionated.

It should answer:

- what changed
- why it matters
- what to watch next

It should not become a second dashboard.

### Case Workspace

This is where analysis happens.

It should hold:

- the current assessment
- evidence
- timeline
- linked assets and actors
- impact chain
- downstream exposure
- scenarios and next checks

## Immediate Priorities

1. Fix production data gaps and weak feeds before adding more domains.
2. Introduce a formal asset and route state model.
3. Rebuild chokepoint and area-impact logic around state change and downstream effects.
4. Demote news from a primary surface to evidence attached to assets, routes, and cases.
5. Focus the product on a small number of high-value chains rather than broad layer coverage.

## Decision Standard

A new feed or layer should only be kept if it improves at least one of these:

- asset significance
- state detection
- consequence detection
- confidence in an existing assessment

If it does not improve one of those, it is probably clutter.
