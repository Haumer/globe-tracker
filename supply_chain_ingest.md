# Supply Chain Ingest

This app now has a raw economic and supply-chain ingest layer built around public or no-key sources, plus a derived normalization and ontology layer on top of it.

## Implemented Sources

- `World Bank WDI`
  - service: `CountryIndicatorRefreshService`
  - cadence: daily via `RefreshCountryIndicatorsJob`
  - storage:
    - `country_indicator_snapshots`
    - `country_sector_snapshots`
  - current series:
    - GDP
    - GDP per capita
    - population
    - imports / exports as % of GDP
    - net energy imports
    - agriculture / industry / manufacturing / services shares of GDP

- `Strategic Trade Flows`
  - service: `TradeFlowRefreshService`
  - cadence: hourly via `RefreshTradeFlowsJob`
  - storage: `trade_flow_snapshots`
  - source mode:
    - `UN Comtrade` keyed API when `COMTRADE_PRIMARY_SECRET` is present
    - optional key failover with `COMTRADE_SECONDARY_SECRET`
    - normalized CSV fallback from `STRATEGIC_TRADE_FLOWS_SOURCE_PATH`
    - normalized CSV fallback from `STRATEGIC_TRADE_FLOWS_SOURCE_URL`
  - automation:
    - polls `getLiveUpdate` to discover newly released reporter-period slices
    - bootstraps the latest available monthly period automatically on an empty DB
    - drains multi-request bootstraps incrementally across runs instead of hammering the API in one pass
    - preserves pending request groups and honors Comtrade `429` cool-down windows automatically
    - fetches only the strategic HS basket used by the app
  - intended upstream sources:
    - `UN Comtrade`
    - `CEPII BACI` fallback if keyed API is unavailable again

- `Energy Balances`
  - service: `EnergyBalanceRefreshService`
  - cadence: daily via `RefreshEnergyBalancesJob`
  - storage: `energy_balance_snapshots`
  - source mode:
    - normalized CSV from `ENERGY_BALANCES_SOURCE_PATH`
    - normalized CSV from `ENERGY_BALANCES_SOURCE_URL`
  - intended upstream sources:
    - `JODI Oil`
    - `JODI Gas`
    - later IMF / IEA if needed

- `Sector Inputs`
  - service: `SectorInputRefreshService`
  - cadence: daily via `RefreshSectorInputsJob`
  - storage: `sector_input_snapshots`
  - source mode:
    - normalized CSV from `SECTOR_INPUTS_SOURCE_PATH`
    - normalized CSV from `SECTOR_INPUTS_SOURCE_URL`
  - intended upstream sources:
    - `OECD ICIO`
    - `OECD TiVA`
    - `OECD BTiGE`

- `Trade Locations`
  - service: `TradeLocationRefreshService`
  - cadence: weekly via `RefreshTradeLocationsJob`
  - storage: `trade_locations`
  - source mode:
    - `World Port Index` feature service by default
    - optional `World Port Index` CSV from `WORLD_PORT_INDEX_SOURCE_PATH`
    - optional override URL from `WORLD_PORT_INDEX_SOURCE_URL`
    - optional `UN/LOCODE` CSV supplement from `TRADE_LOCATIONS_SOURCE_PATH`
    - optional `UN/LOCODE` CSV supplement from `TRADE_LOCATIONS_SOURCE_URL`
  - intended upstream sources:
    - `World Port Index`
    - `UN/LOCODE`
  - supports:
    - normalized `latitude` / `longitude`
    - official `Coordinates` strings like `2516N 05518E`
    - WPI facility attributes such as `Oil Terminal Depth`, `LNG Terminal Depth`, `Cargo Pier Depth`, `Harbor Size`, and `Harbor Use`

## Expected CSV Shapes

The CSV shapes below remain supported for offline backfills and manual recovery, but trade ingest no longer depends on them when Comtrade credentials are configured.

### Strategic Trade Flows

Required:

- `reporter_iso3`
- `partner_iso3`
- `flow_direction`
- `period_start`
- either `commodity_key` or `hs_code`

Optional:

- `reporter_iso2`
- `reporter_name`
- `partner_iso2`
- `partner_name`
- `commodity_name`
- `period_end`
- `period_type`
- `trade_value_usd`
- `quantity`
- `quantity_unit`
- `source`
- `dataset`
- `release_version`

### Energy Balances

Required:

- `country_iso3`
- `country_name`
- `commodity_key`
- `metric_key`
- `period_start`

Optional:

- `country_iso2`
- `period_end`
- `period_type`
- `value_numeric`
- `unit`
- `source`
- `dataset`
- `release_version`

### Sector Inputs

Required:

- `sector_key`
- `input_kind`
- `input_key`
- `period_year`

Optional:

- `country_iso2`
- `country_iso3`
- `country_name`
- `sector_name`
- `input_name`
- `coefficient`
- `source`
- `dataset`
- `release_version`

### Trade Locations

Supported normalized columns:

- `locode`
- `country_iso2`
- `country_iso3`
- `country_name`
- `subdivision_code`
- `name`
- `location_kind`
- `function_codes`
- `latitude`
- `longitude`
- `status`
- `source`

Supported UN/LOCODE-style columns:

- `Country`
- `LOCODE`
- `Name`
- `SubDiv`
- `Function`
- `Coordinates`
- `Status`
- `Ch`

### World Port Index

The app can now ingest WPI directly from the official NGA feature service without a manual file step.

Optional env vars:

- `WORLD_PORT_INDEX_ENABLED`
  - defaults to enabled
- `WORLD_PORT_INDEX_SOURCE_URL`
  - defaults to the official NGA `FeatureServer/0/query` endpoint
- `WORLD_PORT_INDEX_SOURCE_PATH`
  - optional CSV backfill or offline fallback
- `WORLD_PORT_INDEX_SSL_VERIFY`
  - defaults to strict TLS verification
  - set to `false` only if the NGA endpoint presents a broken certificate chain in your runtime environment

Supported WPI fields:

- `wpinumber`
- `main_port_`
- `alternate_`
- `unlocode`
- `countryCode`
- `dodwaterbo`
- `channel_de`
- `anchorage_`
- `cargo_pier`
- `oil_termin`
- `lng_termin`
- `maxvessell`
- `maxvesselb`
- `maxvesseld`
- `harbor_siz`
- `harbor_typ`
- `harbor_use`

## Commodity Mapping

If a trade row does not provide `commodity_key`, the app currently infers it from HS prefixes in `SupplyChainCatalog::STRATEGIC_COMMODITIES`.

Current keys:

- `oil_crude`
- `oil_refined`
- `lng`
- `gas_nat`
- `helium`
- `copper`
- `iron_ore`
- `wheat`
- `fertilizer`
- `semiconductors`
- `semiconductor_equipment`

## Trade API Configuration

For fully automatic trade refreshes, set:

- `COMTRADE_PRIMARY_SECRET`
- `COMTRADE_SECONDARY_SECRET` optional

When those are present, `TradeFlowRefreshService` uses the keyed Comtrade API directly and only falls back to CSV inputs if no Comtrade key is configured.

## Derived Layers

- `SupplyChainNormalizationService`
  - cadence: daily via `RefreshSupplyChainDerivationsJob`
  - storage:
    - `country_profiles`
    - `country_sector_profiles`
    - `sector_input_profiles`
    - `country_commodity_dependencies`
    - `country_chokepoint_exposures`
  - output:
    - latest macro structure per country
    - ranked sector weights
    - ranked sector input coefficients
    - import dependency scores
    - chokepoint exposure scores, including route priors such as `Hormuz -> Malacca -> East Asia energy imports`

- `SupplyChainOntologySyncService`
  - cadence: daily via `RefreshSupplyChainOntologyJob`
  - output:
    - country entities
    - country-sector entities
    - strategic commodity entities
    - `economic_profile` relationships
    - `import_dependency` relationships
    - `production_dependency` relationships
    - `chokepoint_exposure` relationships
    - structural `flow_dependency` relationships from chokepoints to canonical supply-chain commodities

## Current Boundary

This layer now stores raw and cleaned supply-chain data and projects it into the ontology.

It does **not** yet:

- infer facility-to-sector links automatically
- generate dedicated supply-chain insight cards or map layers from the new tables
- maintain a full route-prior table in the database
- model company-level supplier graphs

Those are the next phases.
