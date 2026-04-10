# Regional Profiles Strategy

Repo-wide sourcing rule:

- see `DATA_SOURCING.md`

## Thesis

The current region system is the right foundation, but it is still optimized for geopolitical theaters. To support DACH well, the app should evolve from `region presets` into `regional profiles`.

DACH should be the first profile of this type:

- bounded and easy to enter from the globe
- enriched with regional data that is materially denser than the global baseline
- reusable as the same product pattern for Europe, USA, North America, or other country clusters

## What Exists Already

The repo already has the main primitives:

- preset regions in `app/javascript/globe/regions.js`
- region-mode scoping in `app/javascript/globe/controller/regions.js`
- country and area scoping in `app/javascript/globe/controller/geography_capture.js`
- saved area pages in `app/models/area_workspace.rb` and `app/services/area_summary_service.rb`
- economic and supply-chain ingest in `app/services/supply_chain_catalog.rb`

That means the correct move is not a second parallel product path. It is to formalize a stronger type of region.

## Product Direction

### 1. Dedicated Scope Entry

DACH needs a first-class entry point, not just a manual country selection.

Minimum:

- a `DACH` preset in the region registry
- deep links and saved-area support through existing `preset_region` behavior
- DACH-specific default layers tuned for economic monitoring rather than conflict monitoring

Later:

- a dedicated launcher on the landing page or in the quick bar
- a region page with a stable URL and summary cards

### 2. Regional Data Enrichment

The DACH version should not just show less geography. It should show denser, better data.

Priority domains:

- macro economy
- industrial sites and factories
- power generation and grid context
- cities and regional economic centers
- politics and policy signals

### 3. Reusable Architecture

DACH should be implemented as the first instance of a general pattern:

- `regional profile`
- `regional data packs`
- `regional summaries`

That way, later profiles can reuse the same shape:

- `europe-economic-core`
- `usa-industrial-belt`
- `north-america-energy`

## Proposed Profile Schema

Initial schema can stay config-driven in JavaScript and Ruby. It does not need a database model yet.

Suggested shared shape:

```js
{
  key: "dach",
  name: "DACH",
  group: "Europe",
  mode: "economic",
  countries: ["Germany", "Austria", "Switzerland"],
  bounds: { lamin, lamax, lomin, lomax },
  camera: { lat, lng, height, heading, pitch },
  layers: [...],
  summary_modules: [...],
  data_packs: [...],
  description: "..."
}
```

Important additions beyond the current region object:

- `mode`
  - example: `economic`, `security`, `energy`, `logistics`
- `countries`
  - explicit membership for reuse in summaries and source scoping
- `summary_modules`
  - decides which cards to render on a region page
- `data_packs`
  - names the enrichment bundles required for that profile

## DACH MVP

### Feature Layer

Ship first:

- DACH preset region
- economy-oriented default layers
- dedicated shareable DACH deep link
- saved DACH area workspace support through existing region mechanics

Default DACH layer mix should bias toward:

- borders
- cities
- power plants
- commodity / industrial sites
- pipelines
- airports and NOTAMs
- weather
- outages
- financial overlays
- curated news

### Economic Map Pass

Treat the economic map as a staged build, not a single jump to municipal detail.

Phase 1:

- country-level choropleth for DACH using existing selected-country fills
- compact on-map country badges at centroids
- first metrics: `manufacturing_share_pct`, `gdp_per_capita_usd`, `exports_goods_services_pct_gdp`
- backed by the current source-aware `regional_indicators` country snapshot contract

Phase 2:

- first-order administrative choropleths such as Austrian states, German Länder, and Swiss cantons
- use official regional statistics and reusable `administrative_areas` plus `regional_indicator_snapshots`
- keep the same metric vocabulary as phase 1 where possible

Phase 3:

- district / municipality or other high-resolution local economic surfaces where official coverage is strong enough
- optional 3D extrusion for gross value added, employment, or industrial concentration
- only after boundary quality, joins, and source provenance are reliable

### Data Layer

Add region-specific enrichment in packs, not one-off feeds.

Suggested packs:

1. `economic_baseline`
- GDP, employment, inflation, industrial production
- regional and city-level statistics where available

2. `industrial_sites`
- strategic factories and plants
- logistics hubs
- major exporters
- energy-intensive facilities

3. `power_and_grid`
- power plants
- grid operators
- interconnectors
- outages and balancing context

4. `political_signal`
- parliaments
- ministries
- legislation and committee activity
- election and coalition context

## DACH Data Model Principles

### Source Specific, Model Generic

Even if the first strong data sources are Austrian, the persistence and domain model should stay geography-agnostic.

That means:

- use Austrian data as one source for a generic regional or administrative-area model
- do not create country-named models like `AustrianRegionGdp` or `AustriaFactory`
- do not create DACH-only tables when the same shape will be needed for Europe, USA, or North America

Good abstraction examples:

- `regional_indicator_snapshots`
- `administrative_areas`
- `strategic_sites`
- `political_event_snapshots`

Bad abstraction examples:

- `austrian_states`
- `dach_factories`
- `austria_gdp_snapshots`

The rule is:

- country-specific or provider-specific ingest services are acceptable
- country-specific domain models are not

Political signal needs the same treatment:

- Austria, Germany, and Switzerland will need separate parliament / government / election adapters
- those adapters should all normalize into the shared `political_event_snapshots` contract
- region-level DACH politics should be a summary or aggregation layer, not a DACH-only political schema

City enrichment needs a reproducible sourcing rule too:

- country packs are acceptable, but they must be rebuildable from reliable upstream geography and statistics sources
- manual strategic ranking is acceptable only if the weighting logic or override reason is recorded
- do not let `city_profile_sources` turn into an opaque hand-maintained list with no regeneration path

### Do Not Overfit To Country Boundaries

DACH is not just three countries on one map. The useful unit is cross-border economic structure.

Examples:

- Alpine transit and logistics
- automotive supplier corridors
- power interconnection
- Rhine and Danube industrial chains
- semiconductor, chemicals, steel, machinery, and pharma clusters

### Do Not Require Perfect Factory Coverage

There is unlikely to be a single clean open dataset for every factory. The model should support a mixed source strategy:

- official regulated-facility datasets
- operator / industry association datasets
- curated strategic site catalogs
- geocoded company and plant references

The right abstraction is therefore `strategic sites`, not `all businesses`.

## Suggested Backend Shape

Keep the first version simple and additive.

### Near Term

- keep region definitions in config
- add Ruby service objects that resolve `data_packs` for a region key
- extend area summaries with optional region-profile modules
- normalize all new enrichment into reusable geography models rather than DACH-specific tables

### Likely New Services

- `RegionProfileCatalog`
- `RegionDataPackResolver`
- `RegionSummaryService`
- `StrategicSiteCatalog`
- provider-specific importers such as `AustriaRegionalIndicatorImportService`

### Likely New Tables Later

- `administrative_areas`
- `strategic_sites`
- `strategic_site_snapshots`
- `regional_indicator_snapshots`
- `political_event_snapshots`

## Modeling Guidance

### Geography Hierarchy

The reusable geography model should be able to hold:

- country groups like DACH
- countries
- first-order administrative units like Austrian states, German Länder, Swiss cantons
- cities and metro areas

That implies identifiers and labels should not assume one national system only.

Suggested attributes:

- `geography_kind`
- `country_code`
- `country_code_alpha3`
- `admin_level`
- `external_source`
- `external_id`
- `name`
- `parent_geography_id`
- geometry or bounds

### Indicator Shape

Economic metrics should be modeled as generic observations attached to a geography, not as custom columns for one country.

Suggested indicator shape:

- geography reference
- indicator key
- indicator name
- period type
- period start
- period end
- value numeric
- unit
- source
- dataset
- release version

This allows Austrian state GDP, German Land unemployment, Swiss canton population, and later US state indicators to share the same contract.

## Future Expansion

If this works for DACH, the next reusable profiles are obvious:

- Europe economic core
- USA
- North America

Those should reuse the same contract:

- bounded profile
- explicit country set
- curated layers
- region-specific data packs
- dedicated summary modules

## Immediate Next Steps

1. Keep DACH as a first-class preset region.
2. Define the first `data_packs` contract in code, even if it is still config-backed.
3. Start with one strategic-site catalog for DACH rather than trying to ingest every company dataset at once.
4. Add a DACH summary view that emphasizes economy, industry, energy, and politics instead of conflict theater language.
