# Design Seriousness — Bookmarked Work

## Completed
- Anchor panel (map marker window) redesigned: flat, 2px radius, Inter titles, inline header with title/chips/time/close
- Right panel fully restyled: docked flush, flat backgrounds, Inter/Mono type system, desaturated palette, terse copy
- Theater context restructured into 3 sections: Situation / Recommended Actions / Deep Dive
- JS-computed "so what" from nearby infrastructure (chokepoints, power plants, cameras, military bases)
- Recommended actions engine (smart layer suggestions from zone signals + layer state)
- AI prompt sharpened (gpt-4.1-mini, cross-layer synthesis, no metric restatement, no infrastructure claims)
- Client-side fallback improved (signal convergence narrative instead of number readback)
- Duplication fixed (assessment renders once)
- Details collapse fix (open state preserved across re-renders)
- Time format unified to "4. Apr. 10:30"
- Empty state copy terse uppercase
- "What changed" delta tracking: client-side memory stashes zone metrics per cell_key, shows deltas on re-render
- Key developments: only AI-generated bullets shown, raw article list removed
- Left sidebar restyled: flat backgrounds, Inter/Mono, steel accent, 2px radii, no blur/glass
- Sidebar header added with close button, floating toggle hides when sidebar open
- Sidebar inline rainbow colors stripped from ERB (section dots, icon colors, chip colors)

## Still TODO
- Set OPENAI_API_KEY in worktree env to test AI brief generation with sharpened prompt
- Server-side history (Option B): add previous_payload to LayerSnapshot for offline deltas. Lower priority.
- Force-regenerate stale AI briefs for active theaters.
- JS presenter cleanups: news_feed.js, insight_presenters.js, alerts.js still inject some inline styles at runtime.

## Design Philosophy (agreed)
- AI assessment: interprets signal convergence MEANING, never restates metrics or claims infrastructure knowledge
- "So what": JS-computed from app's own data. Factual, not LLM.
- "What changed": client-side delta tracking, honest about session scope
- Recommended actions: JS logic from zone signals + current layer state. Clickable.
- Deep dive: collapsible details for evidence basis, corroboration, watch next. Not the default view.
- Key developments: AI-only (no raw article list)
- Panel goal: "should I care?" → "how solid?" → "what changed?" → "what do I do next?"
