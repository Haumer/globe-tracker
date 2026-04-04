# Design Revamp

## Intent

The current globe UI feels overloaded in two places:

1. The left sidebar exposes too many layers at once.
2. Clicking an object opens heavy UI that is visually detached from the thing that was clicked.

This revamp should reduce cognitive load, keep the map visible, and make interactions feel attached to the data instead of attached to the chrome.

## Core Principles

- Derived and aggregate signals should be the default entry point.
- Raw layers should exist, but stay out of the way until explicitly enabled.
- A click should start with lightweight local inspection, not global panel takeover.
- The right-side panel should be for exploration and browsing, not the default response to every click.
- Map overlays should be compact, anchored, and dismissible.

## 1. Sidebar Simplification

### Problem

The current sidebar is a hardcoded catalog of nearly every layer in the system. It makes the product feel like a control panel before the user has any idea what matters.

### New Model

Separate three states that are currently conflated:

- `surfaced`: shown in the sidebar by default
- `enabled`: available in the current signed-in workspace
- `visible`: currently turned on
- `revealed`: surfaced temporarily because a preset, region, deep link, or workspace activated it

### Default Surfaced Set

Start with a small primary set:

- `situations` shown in the UI as `Conflict Theaters` or `Theaters`
- `insights`
- `news`

If this still feels too busy, reduce the default set further to:

- `situations`
- `insights`

### Advanced Layers

Everything else becomes advanced:

- tracking
- military
- infrastructure
- cyber
- map utility layers
- specialized event layers

Advanced layers should:

- stay hidden for logged-out users
- be enableable by signed-in users
- remain hidden from the main sidebar until enabled
- appear in a separate secondary section once enabled
- also appear there when a preset or region activates them, even for logged-out users

### Sidebar Structure

Replace the current section stack with:

1. `Primary Signals`
2. `Additional Layers` (enabled or temporarily revealed by the current view)
3. `Enable More Layers` / `Layer Library`

The sidebar should stop trying to be the entire product index.

### Persistence

Persist `enabled_layers` separately from `visible` layer state.

- `enabled_layers` belongs in user preferences
- workspaces can auto-enable advanced layers they depend on
- visibility remains a session/workspace state

## 2. Click Interaction Redesign

### Problem

Single clicks currently open a large detail panel in the bottom-right while a large right-side panel also exists. This makes the interface feel slow, heavy, and visually disconnected from the clicked object.

### New Interaction Model

Use a two-stage inspection flow:

1. `Single click` opens a compact anchored callout attached to the object with a leader line.
2. `Open more` escalates to a richer right-side panel only when needed.

### Anchored Inspector

The first-stage click UI should:

- appear near the clicked object
- draw a leader line from object to card
- stay compact
- reposition intelligently if near the screen edge
- follow the object while the camera moves
- close cleanly when clicking elsewhere

### Contents of the Anchored Card

Keep it short:

- title
- type
- 2-4 key values
- 1-2 actions

Example actions:

- `Track`
- `Focus`
- `Open details`
- `Open source`
- `Add to case`

### What Should Use the Anchored Inspector

First-wave entities:

- flights
- ships
- situations / theaters
- insights
- chokepoints
- webcams
- earthquakes
- fires
- outages

### What Should Stay in the Right Panel

The right panel should become the place for:

- browsing many entities
- news feed exploration
- insights feed exploration
- situations lists
- context graph inspection
- alerts
- cameras feed

It should not open automatically for every point click.

## 3. Right Panel Role Cleanup

The right panel should be reframed as a browsing rail, not a universal details drawer.

New role:

- feed browsing
- list browsing
- multi-item context
- deeper analysis

Reduced role:

- single-point detail inspection

## 4. Visual Behavior Rules

To keep the UI from obscuring the map:

- only one anchored inspector at a time
- do not auto-open the right rail on single object click
- avoid large modal behavior on the map canvas
- keep default cards narrow and vertically compact
- preserve the clicked object as the spatial reference point

## 5. Implementation Phases

### Phase 1: Sidebar Gating

- add layer metadata for `surfaced_by_default` and `advanced`
- add `enabled_layers` preference persistence
- reduce the sidebar to `Primary Signals`
- add `Workspace Layers`
- add `Enable More Layers`

### Phase 2: Anchored Inspector

- build a generic anchored callout component
- draw an SVG or canvas leader line
- attach it to Cesium screen coordinates
- replace the fixed detail panel as the default click target

### Phase 3: Right Panel Cleanup

- reserve right panel for feeds and lists
- remove automatic panel takeover for single-entity clicks
- make `Open details` an explicit action from the anchored card

### Phase 4: Content Migration

- convert layer-by-layer detail renderers to compact summary cards
- keep deeper content available in the right panel when needed

## First Build Recommendation

Build in this order:

1. sidebar simplification
2. anchored inspector
3. right panel role cleanup

That sequence fixes the two biggest UX problems first:

- too much to turn on
- too much UI when something is clicked
