# Data Sourcing Standard

This repo should treat source provenance as a hard requirement, not a nice-to-have.

## Core Rule

Every dataset we add or enrich must have a documented upstream source.

That applies to:

- curated JSON snapshots
- imported CSVs
- API-backed ingests
- manually reviewed source packs
- region-specific enrichment such as DACH, Austria, Europe, USA, or North America

If we cannot explain where a dataset came from and how to get it again, it should not become a durable part of the product.

## Minimum Source Record

Every dataset or source pack should record:

- `source_name`
- `source_url` or a documented retrieval path
- refresh cadence when known
- access mode
  - public file
  - public API
  - authenticated API
  - reviewed snapshot
- target generic model or normalization contract
- any important license or reuse constraints
- any manual override rules

For file-based source packs, this can live in:

- the records themselves
- a manifest
- an adjacent README
- an importer service with a clear constant or comment pointing to the upstream source

## Rebuildability

The standard is not "fully automated or it does not count."

The standard is:

- another engineer should be able to recover the same candidate dataset later
- the weighting logic should be understandable
- manual edits should be explicit and limited

Acceptable:

- official dataset plus documented scoring logic
- operator snapshot plus source URL and rebuild task
- curated shortlist derived from official sources with recorded inclusion criteria

Not acceptable:

- opaque hand-entered lists with no provenance
- "someone looked this up once"
- country or region catalogs that cannot be regenerated from documented upstream inputs

## Generic Models

Source-specific and country-specific ingest is acceptable.

Source-specific and country-specific domain models are not the default.

The expectation is:

- provider-specific importers normalize into shared contracts
- country packs remain source organization, not schema organization
- regional products like DACH summarize shared models rather than inventing one-off tables

## Manual Overrides

Manual overrides are allowed when they add real product value, but they must be recorded.

Each override should document:

- what changed
- why the base source was insufficient
- what source justified the override

## Working Rule

Before adding data, ask:

1. What is the upstream source?
2. How do we fetch or reconstruct it again?
3. What generic model should it normalize into?
4. Which parts are sourced and which parts are editorial judgment?

If those answers are not clear, the data is not ready to become part of the repo.
