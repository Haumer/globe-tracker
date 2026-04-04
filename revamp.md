# Revamp Prep

This file is intentionally local and untracked.

## Goal

Refactor the app into a cleaner base for a broader platform revamp without changing current behavior.

## Priorities

1. Break up monolithic frontend controller files into smaller helper modules.
2. Reduce lifecycle complexity in the globe controller and make setup/teardown explicit.
3. Move bulky presentation-building code out of controller methods.
4. Split large Ruby service constants/orchestration from rule implementation where safe.
5. Preserve behavior, then verify with focused tests and syntax checks.

## First Pass

- Extract globe controller boot state and teardown helpers from `core.js`.
- Extract context rendering helpers from `context.js`.
- Extract insight feed/detail presentation helpers from `insights.js`.
- Extract `CrossLayerAnalyzer` constants/rule registry into a dedicated support file.
- Run focused regression tests after each cleanup slice.

## Follow-Up

- Split `ontology_relationship_sync_service.rb` into relationship family modules.
- Split `conflictPulse.js`, `situational.js`, and `selection.js` by feature area.
- Introduce app-wide presenter/helper patterns for repeated HTML string rendering.
- Add lightweight linting/static checks so future file growth is caught earlier.
