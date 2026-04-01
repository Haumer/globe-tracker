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
  - cadence: daily via `RefreshTradeFlowsJob`
  - storage: `trade_flow_snapshots`
  - source mode:
    - normalized CSV from `STRATEGIC_TRADE_FLOWS_SOURCE_PATH`
    - normalized CSV from `STRATEGIC_TRADE_FLOWS_SOURCE_URL`
  - intended upstream sources:
    - `CEPII BACI`
    - `UN Comtrade` when access is available again

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
    - CSV from `TRADE_LOCATIONS_SOURCE_PATH`
    - CSV from `TRADE_LOCATIONS_SOURCE_URL`
  - intended upstream sources:
    - `UN/LOCODE`
  - supports:
    - normalized `latitude` / `longitude`
    - official `Coordinates` strings like `2516N 05518E`

## Expected CSV Shapes

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
