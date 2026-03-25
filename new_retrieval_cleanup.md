# Retrieval Outstanding

This file tracks only remaining retrieval and source-expansion work.

## Current Goal

Only add retrieval that improves:

- corroboration quality
- strategic node coverage
- operator / ownership context
- consequence tracing

## Open Retrieval Work

### 1. MediaCloud

Use `MEDIA_CLOUD_TOKEN` to improve:

- story discovery breadth
- chokepoint-specific reporting
- theater-level corroboration
- more durable multi-source cluster support

This is the highest-priority new source lane.

### 2. ReliefWeb

Use `RELIEF_WEB_APP_NAME` for structured crisis and humanitarian coverage:

- disasters
- displacement
- aid / response
- infrastructure and civilian consequence reporting

This is especially useful for:

- `news -> observed event`
- `event -> consequence`
- humanitarian and disaster desks

### 3. Strategic Anchors

Add missing datasets that make global relationships stronger:

- ports
- cable landing stations
- ASN / ISP / telecom operator metadata
- better operator / owner metadata for infrastructure

### 4. Satellite Semantics

Do not add more satellite rows blindly.
Add observation usefulness:

- sensor type
- footprint / pass events
- observation plausibility for a time window

## Not Retrieval Work

These belong elsewhere and should not be mixed back into retrieval:

- ontology expansion for its own sake
- relationship builders
- frontend context rendering
