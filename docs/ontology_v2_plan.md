# Ontology v2 Plan

## Why this exists

The current ontology is not usable as the main analytical backbone yet. It stores many objects, but the event graph and relationship graph are effectively disconnected. A concrete example is Kuwait: the state actor, country, and place records can exist as separate records, while only one carries event links and another carries economic links. That means downstream layers can miss the real question: what happened, where, to whom, and what connected infrastructure or markets does it affect?

Ontology v2 should be built alongside the current ontology first, not as a blind in-place refactor. The goal is to prove the model with a narrow slice, then backfill and migrate.

## Model Direction

Objects should represent real-world things, not source-system artifacts:

- `Country`
- `Actor`
- `Organization`
- `AdminRegion`
- `City`
- `Facility`
- `Port`
- `Airport`
- `MilitaryBase`
- `PowerPlant`
- `Cable`
- `Corridor`
- `Commodity`
- `Sector`
- `Vessel`
- `Aircraft`
- `Event`
- `Claim`
- `Evidence`
- `Situation`

Identity rules need to be explicit. For example, `Kuwait` as a country, `Kuwait` as a state actor, and `Kuwait` as a place cannot be free-floating duplicates. If they remain separate objects, the system must create typed links like `Actor represents Country`, and downstream code must traverse through the canonical identity graph.

## Event Rules

Events should be first-class and must carry enough structure to support analysis:

- event type and family
- time window
- status
- verification status
- confidence
- location or affected geography
- evidence links
- typed participants such as actor, target, affected party, affected asset, host, reporter, corroborator

Claims are not facts. News creates claims. GeoConfirmed data, official statements, sensor data, and corroborated reporting create evidence. Events should be promoted or updated from claims/evidence based on thresholds, not directly treated as truth because a headline mentions a place.

## Link Rules

Use typed links only. Avoid generic `related_to`.

Examples:

- `Actor launched Event`
- `Event targeted Facility`
- `Facility located_in AdminRegion`
- `AdminRegion part_of Country`
- `Port serves Commodity`
- `Cable lands_at CableLandingStation`
- `Event disrupted Port`
- `Situation affects Country`
- `Situation involves Event`
- `Actor represents Country`

This is the critical change: analysis should be graph traversal over typed links, not keyword grouping.

## First Slice

Build a canonical identity layer and graph health checks before rebuilding all ontology ingestion.

Initial implementation:

- Add a service that resolves equivalent country/state/place records into a canonical identity view.
- Backfill or derive mandatory `Actor represents Country` links for state actors where possible.
- Add tests for Kuwait/Iran-style identity fragmentation.
- Add graph health checks that report disconnected country/actor/place duplicates.
- Do not insert every ship or aircraft into the analysis ontology unless it is promoted into a situation, event, or relevant asset class.

## What This Unlocks

Situation and disruption layers should be built from the ontology graph:

- recent events
- affected entities and assets
- resolved geography
- severity and scope
- evidence and confidence
- rendered surface or narrative

That means a strike in Kuwait should connect to the target, the facility, Kuwait as a country, Gulf energy infrastructure if relevant, commodity exposure if relevant, and only then produce a map surface or AI assessment.

## Non-Goals For The First Slice

- Do not rebuild every importer at once.
- Do not make a new UI first.
- Do not treat AI prose as the ontology.
- Do not bulk-promote raw live ship/flight rows into ontology objects unless they are tied to an event or situation.
- Do not merge the experimental situation-surfaces branch into this work until the ontology substrate is cleaner.
