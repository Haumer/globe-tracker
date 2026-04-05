# Globe Context, Rail, and Case Flow Plan

## Goal

Restructure the product into three linked surfaces:

1. `Spatial context`: map marker + anchored window on the globe
2. `Context rail`: a stripped-down right panel with only topline node context
3. `Case workspace`: the separate deep-dive view for analysis, timeline, evidence, and derived graphs

The core principle is: the globe is for orientation, the rail is for quick understanding, and the case is for actual work.

## What The Reference Images Suggest

### Structural lessons worth borrowing

- The map should remain the primary surface.
- Detail should sit near the thing it describes whenever possible.
- Derived analysis views need room and should not be squeezed into a sidebar.
- Timeline, scenario, dependency, reserve runway, and flow/exposure views read better as dedicated analytical modules than as sidebar cards.

### Structural lessons to avoid copying literally

- Do not copy the faux telescope / classified styling.
- Do not overload the UI with decorative labels and ultra-small text.
- Do not turn the app into a cinematic mockup that sacrifices readability.

## Proposed Surface Model

## 1. Spatial Context On The Globe

This becomes the first-response surface.

### Role

- Answers: `what is this thing, where is it, and why should I care right now?`
- Lives directly on the map through the anchored window.
- Should feel fast, spatial, and low-friction.

### Window content

For theaters, chokepoints, stories, and other node types, the anchored window should stay compact and consistent:

- title
- node type / status pill
- one-line context or parent grouping
- 2-3 critical metrics
- one short current-read sentence when warranted
- actions

### Required controls

Each anchored window should support:

- `Pin` / `Unpin`
- `Show in rail`
- `Open case workspace`
- `Close`

### Pinning model

- Default click opens one active anchored window.
- `Pin` converts it into a persistent anchored card tied to the map position.
- Pinned cards survive camera movement and selection changes until explicitly closed or unpinned.
- The active, unpinned card can change with selection.
- Do not impose a hard cap on pinned nodes.
- Add a clear global `Unpin all` action because unlimited pinning without a bulk clear will become unmanageable.

### Pinning vs tracking

These should be treated as different user intents:

- `Pinned`
  - temporary spatial comparison on the globe
  - tied to anchored windows
  - user is visually comparing nodes in-map

- `Tracked`
  - durable monitoring intent
  - should survive beyond the immediate map session
  - should integrate with the existing watch/alert model rather than being just another pin

Pinning is for visual working memory. Tracking is for ongoing surveillance.

### Why this matters

This keeps the product map-native. A user can compare spatially distinct nodes without immediately being forced into a side panel or a case page.

## 2. Context Rail On The Right

This becomes a thin, readable context strip, not a second application.

### Role

- Answers: `what is happening across the currently selected or pinned nodes?`
- Provides topline understanding only.
- Does not try to be the full dossier.

### Strong recommendation

Remove the current top-level tab model as the primary mental model for this surface.

The current `Context / News / Situations / Insights` split is still too system-shaped and not user-shaped. The rail should instead be a single `Context rail` with stacked node summaries.

### What belongs in the rail

For the active node and, where relevant, pinned non-theater nodes:

- title
- node type / status
- one short assessment
- why it matters now in 1-3 bullets or signals
- last updated
- jump/focus action
- open case workspace action

### What does not belong in the rail

- large evidence lists
- long article streams
- deep graph traversals
- derived flow/dependency/reserve visualizations
- diplomacy or scenario timelines
- layer-discoverability clutter as first-class content

### Suggested rail structure

- `Active node`
- `Pinned nodes`
- optional compact `Watchlist` section later

This supports “potentially multiple nodes” without turning the rail into another tabbed dashboard.

### Conflict-theater rule

For conflict theaters specifically, only the currently active theater should show the full context summary in the rail.

Rationale:

- theater context is dense and quickly becomes repetitive if multiple theaters are expanded at once
- the globe itself already handles multi-theater comparison spatially
- the rail should clarify the active operating picture, not mirror every pinned theater

Pinned theaters can still exist on the globe, but the rail should treat one theater as primary at a time.

## 3. Case Workspace As The Deep-Dive Surface

This is where the product becomes analytical.

### Role

- Answers: `what is the full picture, what supports it, how could it evolve, and what should I do next?`
- Reuse and evolve the existing `investigation_cases` surface rather than inventing a parallel deep-dive destination.

### Current app pieces to reuse

- `app/views/investigation_cases/show.html.erb`
- `app/views/investigation_cases/new.html.erb`
- `app/controllers/investigation_cases_controller.rb`
- `app/helpers/investigation_cases_helper.rb`

### Proposed case workspace structure

- `Header`
  - case title
  - status
  - severity
  - owner / assignee
  - return-to-globe action

- `Executive brief`
  - current read
  - why we believe it
  - watch next
  - recommended actions

- `Timeline`
  - diplomacy / escalation chronology
  - key developments
  - market reaction or prediction overlays where relevant

- `Evidence and linked nodes`
  - pinned objects
  - notes
  - supporting stories
  - related entities

- `Derived analysis`
  - chokepoint flow graph
  - dependency map
  - reserve runway
  - disruption scenario views

### Where the reference-image derived views fit

The images you shared should live here, not in the right rail:

- `Oil flow converge & choke` -> `Flow analysis`
- `Hormuz oil dependency` -> `Dependency analysis`
- `How long can they last?` -> `Reserve runway`
- `Diplomacy timeline` -> `Timeline / scenario module`

Those are case modules because they are interpretive and comparative, not glanceable context.

## 4. Bottom Time Surface

This should become a real second workspace, not just a narrow utility strip.

### Role

- supports time travel
- exposes event density and change over time
- provides quick comparison and filter controls while staying map-adjacent

### Direction

Make the bottom surface wider and more informative, closer to the reference images:

- wider timeline track
- clearer event density / cluster markers
- easier date-range control
- better cursor readability
- more room for filters and derived context

### What belongs in the bottom surface

- improved event timeline
- active filters
- playback / time-travel controls
- compact change summaries
- country chips or selection controls for the current active theater
- optional scenario / comparison toggles later

### Time-linked graph behavior

Any graph shown alongside time travel should be linked to the active playback cursor.

Example:

- if the user is in a `3-day` playback window
- and a graph shows that same `3-day` range
- the currently selected playback time should be visibly highlighted inside the graph

That highlight can be expressed as:

- a vertical cursor line
- a focused point marker
- a highlighted bucket or band
- or a narrow time window overlay, depending on the graph type

The key rule is that map time and graph time must move together. The user should never have to guess which point in the graph corresponds to the time currently shown on the globe.

### Time-scope rule

Graphs should either:

- match the active playback window exactly, or
- clearly show how the active playback window sits inside a larger range

If the graph covers a larger period than the current playback window, the UI should show both:

- the playback cursor
- the current playback range

This is especially important for:

- event-count graphs
- resource flow graphs with time-series overlays
- price or risk charts
- diplomacy / escalation timelines

### Country-selection behavior

Use the bottom surface as the main place for country focus and comparison controls.

For a theater like `Middle East / Iran War`, the product should be able to preselect directly involved countries programmatically, for example:

- countries implied by the active theater definition
- countries inferred from situation-name and theater mapping
- countries inferred from claim/news actors when available

The goal is not perfect geopolitical modeling on day one. The goal is a useful default actor footprint that the user can refine.

### Why this matters

Time travel is a core product capability, not a utility afterthought. The current mini-timeline is too narrow and low-context for that role.

## 5. Resource Semantics For Infrastructure Layers

The infrastructure layers should not just show `where assets are`. They should also communicate `what resource they carry, consume, produce, or constrain`.

This is especially valuable for:

- pipelines
- power plants
- chokepoints
- ports and export terminals later

### Why this matters

The reference image is useful because it makes infrastructure operationally legible:

- what is moving
- where it is moving
- what the current regime is
- what the economic or energy consequence is

That is stronger than a generic “asset marker” model.

### Pipeline layer direction

Pipelines should expose:

- transported resource
  - oil
  - gas
  - refined products
  - later: hydrogen / multiproduct where relevant
- approximate route role
  - export
  - domestic transfer
  - bypass / redundancy
- throughput or capacity when available
- operational state
  - operational
  - constrained
  - under construction
  - proposed
  - damaged

### Power plant layer direction

Power plants should expose:

- input fuel
  - coal
  - gas
  - oil
  - nuclear
  - hydro
  - solar
  - wind
- output
  - electricity
- generating capacity
  - MW / GW
- strategic role when inferable
  - baseload
  - peaking
  - industrial support
  - export-linked or grid-critical where we can derive it later

### Product behavior

This can work across all three surfaces:

- `Anchored window`
  - quick resource label plus one or two operational metrics
- `Context rail`
  - compact resource summary only
- `Case workspace`
  - full resource-flow and consequence analysis

### Recommended first pass

Do not try to solve every infrastructure class at once.

Start with:

1. `Pipelines`
   - resource carried
   - status
   - route role
   - capacity / length where available

2. `Power plants`
   - fuel in
   - electricity out
   - capacity
   - country / grid importance hints later

3. `Chokepoints`
   - resource flow exposure
   - dependency
   - disruption consequence

### Data reality in the current app

The app already has partial support for this:

- pipelines expose `type`, `status`, and `length` today
- power plants expose `primary_fuel`, `capacity_mw`, and country today
- there is already supply-chain / chokepoint / commodity infrastructure in the repo that can support richer exposure views later

So this is not speculative. It is a real next-layer interpretation pass over data we mostly already have.

## Linking The Three Surfaces

All three surfaces should be navigationally linked and reversible.

### From the anchored window

Actions:

- `Show rail`
- `Open case workspace`
- `Pin`

### From the context rail

Actions on each node summary:

- `Focus on globe`
- `Activate / bring to front`
- `Open case workspace`
- `Unpin` when relevant
- `Track` / `Untrack` when relevant

### From the case workspace

Actions:

- `Return to globe`
- `Open object on globe`
- `Restore prior globe state`

## State Model

This is the critical architecture piece.

We already have partial building blocks:

- `app/javascript/globe/deeplinks.js` encodes camera/layer/filter state in the URL hash
- `focus_kind` / `focus_id` query params reopen a focused object
- case objects already generate `Open On Globe` links

### Problem

Current state restoration is partial:

- camera and visible layers can be restored
- a focused node can be restored
- pinned anchored windows, active rail state, and multi-node context are not yet part of the same model

### Proposed unified globe state

Define a single `globe context state` object:

- camera
- enabled layers
- filters / region / circle / countries
- timeline/playback state
- active node
- pinned node list
- tracked node references
- right rail open/closed
- rail ordering
- active theater
- bottom surface state
- optional selected case id

### Recommended transport

Use two levels of state:

- `Shareable state`
  - URL-based
  - derived from `encodeState` / `decodeHash`
  - supports camera, layers, filters, active node, pinned nodes, active theater

- `Session return state`
  - ephemeral state for “take me back exactly where I was”
  - stored in `sessionStorage`
  - includes UI-specific pieces like open anchored cards, rail state, bottom surface state, and active case return target

### Why both are needed

- URL state is good for links, reloads, and shareability
- session return state is better for the exact “leave globe -> inspect case -> come back to same state” loop

## Proposed Navigation Rules

### Globe -> Case

When opening a case workspace from the globe:

1. Save the full current globe context state to `sessionStorage`
2. Pass stable object/case identifiers in the URL
3. Optionally pass a shareable hash for durable restoration

### Case -> Globe

When returning from a case workspace:

1. Restore the last saved session globe state if it exists
2. Fall back to durable URL state if needed
3. Fall back to object focus if neither exists

This gives us a deterministic return path instead of loose best-effort behavior.

## Concrete Product Changes

## Phase 1: Simplify The Globe Surfaces

- keep anchored window as the primary selection surface
- add explicit `Pin` / `Unpin`
- add global `Unpin all`
- keep `Track` as a separate action from pinning
- replace the current right-panel tab model with a single context rail
- right rail shows active node context and compact pinned-node context
- for conflict theaters, only show the active theater dossier in the rail

## Phase 1B: Upgrade The Bottom Surface

- widen the bottom section materially
- turn the mini-timeline into a more legible event timeline
- preserve time-travel controls there or make it the launch surface for the full playback bar
- use the bottom surface for active-theater filters and comparison controls
- allow direct country selection from the active theater context

## Phase 2: Unify Globe State

- extend deep-link state to include:
  - active node
  - pinned nodes
  - tracked nodes
  - rail state
  - active theater
  - bottom surface state
- add session restore for exact return-to-globe behavior
- make case links carry or recover that state consistently

## Phase 3: Repurpose The Case Surface

- evolve `investigation_cases#show` from a management page into an analysis workspace
- keep notes and pinned objects
- add:
  - executive brief
  - key developments timeline
  - scenario / prediction modules
  - derived views tabs or sections

## Phase 4: Derived Analysis Modules

Start with chokepoints and oil/LNG because the visual models are strongest there.

- `Flow`
- `Dependency`
- `Reserves`
- `Timeline`

Each module must clearly show:

- data basis
- timestamp
- assumptions
- whether it is observed vs modeled

## Concrete File-Level Direction

### Globe / spatial context

- `app/views/pages/home.html.erb`
- `app/javascript/globe/controller/detail_overlay/*`

### Context rail replacement

- `app/views/pages/_right_panel.html.erb`
- `app/javascript/globe/controller/context.js`
- `app/javascript/globe/controller/context_presenters.js`
- `app/javascript/globe/controller/context_sections.js`
- `app/javascript/globe/controller/situational_right_panel.js`
- `app/javascript/globe/controller/ui_panel.js`

### State handoff

- `app/javascript/globe/deeplinks.js`
- `app/javascript/globe/controller/core.js`
- `app/helpers/investigation_cases_helper.rb`

### Bottom time/filter surface

- `app/views/pages/_bottom_strip.html.erb`
- `app/views/pages/_timeline.html.erb`
- `app/javascript/globe/controller/mini_timeline.js`
- `app/javascript/globe/controller/timeline*.js`
- `app/assets/stylesheets/pages/home/_bottom.scss`

### Case workspace evolution

- `app/views/investigation_cases/show.html.erb`
- `app/views/investigation_cases/new.html.erb`
- `app/controllers/investigation_cases_controller.rb`

## Open Questions To Resolve Before Building

1. How exactly should `tracked` items surface in the UI: in the rail, in the bottom surface, in cases, or across all three?
2. Should `pinned` nodes persist only in-session, while `tracked` nodes become durable user watches?
3. Should opening a case always create/select a case immediately, or should there also be a “temporary dossier” view before formal case creation?
4. Should `News` survive as a separate full-screen or drawer surface, or be folded into the case workspace entirely?
5. How should programmatic country selection work for theaters with ambiguous or diffuse actors?

## Recommended Build Order

1. Replace the right-panel tabs with a single context rail
2. Add anchor pinning, `Unpin all`, and separate `Track` behavior
3. Upgrade the bottom strip into a wider time/filter surface
4. Add active-theater country selection and programmatic actor-based country presets
5. Implement exact globe-state return from case workspace
6. Repurpose the case show page into the real deep-dive view
7. Add the first derived module for chokepoints: `Flow`
8. Add `Dependency`, `Reserves`, and `Timeline`

## Recommendation

Proceed with the three-surface model.

It matches the strongest ideas from the reference images without copying their theatrical presentation:

- map-first interaction
- anchored spatial context
- restrained quick context rail
- dedicated analytical deep-dive workspace

This is a cleaner product model than continuing to refine the current right-sidebar-as-everything approach, and it gives the time-travel system and theater/country context a proper home.
