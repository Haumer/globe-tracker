# Globe Tracker — Frontend Redesign Phases

## Phase 1: Bottom Strip Consolidation ✓
Merge controls-bar, mini-timeline, and controls-hint into one `#bottom-strip` with three sections:
- **Left**: Active-layer pills (colored dots + abbreviated names of all active layers)
- **Center**: Mini-timeline dots (24h event visualization)
- **Right**: Controls (zoom, reset, views, record, screenshot, share, timeline)

Timeline bar stays separate, slides up from bottom strip when activated.

## Phase 2: Stats Bar Cleanup ✓
- Remove all inline styles from `_stats_bar.html.erb`, move to CSS classes
- Add right-panel toggle button (persistent way to reopen after closing)
- Standardize z-index

## Phase 3: Right Panel Persistence ✓
- Fix "can't reopen" bug — stop auto-hiding when no tabs have data
- Track `_rightPanelUserClosed` boolean
- Show empty state when no data ("Enable layers to see data here")
- Store open/closed state in preferences
- Entities tab always visible

## Phase 4: Sidebar Refinement ← CURRENT
- Move hidden `<input type="checkbox">` toggles out of visible "Map & Tools" section
- Add active layer count badge on sidebar toggle button
- Make active quick-bar buttons more prominent (pulse dot)
- Clean up "Map & Tools" to only contain terrain, buildings, selection tools

## Phase 5: Mobile Layout Overhaul
- Bottom strip: scrollable active-layer pills + "more" button for controls
- Sidebar: swipe-down to dismiss, simplify peek/expand cycle
- Right panel: half-screen bottom sheet instead of fullscreen overlay (z:200)
- Detail panel: cap at 30vh, add minimize to single-line summary bar
- Verify all touch targets are 44px+

## Phase 6: Event Alert System
- "Event significance" thresholds (M6+ earthquake, eruption, major conflict, extreme weather)
- Event banners below stats bar, shown even when layer is off
- "Show" button enables layer + flies to event, "X" to dismiss
- Auto-dismiss after 30s, max 3 banners visible
- Reuses alert-toast styling with colored borders

## Phase 7: z-index Normalization & Polish
Strict z-index system:
- 10: Sidebar
- 20: Bottom strip
- 30: Right panel
- 40: Detail/floating overlays
- 50: Stats bar
- 60: Event banners
- 100: Onboarding
- 200: Tooltips/toasts

Remove all inline z-index from HTML. Remove unnecessary `!important` overrides.

---

## Data Improvements (noted during audit)
- EVT count only shows active layers — should always count all events, indicate hidden vs shown
- Preferences lost if tab closed within 2s debounce — add `beforeunload` save
- Mini-timeline DOM re-renders on every cycle — consider canvas
- Satellite badge doesn't clear properly at count 0
