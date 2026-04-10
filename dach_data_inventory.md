# DACH Data Inventory

Repo-wide sourcing rule:

- see `DATA_SOURCING.md`

## Goal

Identify realistic data sources to enrich a dedicated DACH profile without creating DACH-specific or country-specific domain models.

The working rule from this branch remains:

- ingest can be source-specific
- storage and application models must stay generic

## Recommended Generic Models

| Model | Purpose | Typical keys |
| --- | --- | --- |
| `administrative_areas` | countries, states, cantons, districts, municipalities, metro areas | `geography_kind`, `country_code`, `admin_level`, `external_source`, `external_id`, `name` |
| `regional_indicator_snapshots` | GDP, employment, sector mix, inflation, population, commuters | `administrative_area_id`, `indicator_key`, `period_start`, `value_numeric`, `unit`, `source`, `dataset` |
| `strategic_sites` | factories, industrial facilities, logistics hubs, critical plants | `site_kind`, `operator_name`, `industry_code`, `latitude`, `longitude`, `country_code`, `source` |
| `power_assets` or existing `power_plants` plus extensions | generation plants, substations, interconnectors | `asset_type`, `fuel_type`, `capacity_mw`, `operator_name`, `latitude`, `longitude`, `source` |
| `political_event_snapshots` | bills, votes, parliamentary agenda items, election results, referenda | `jurisdiction_key`, `event_kind`, `occurred_at`, `status`, `source`, `payload` |

## High-Value Sources

### 1. Administrative Areas And Cities

| Source | Coverage | Granularity | Update | Best fit | Notes |
| --- | --- | --- | --- | --- | --- |
| Eurostat GISCO NUTS / LAU / cities | Austria, Germany, EU-wide | NUTS 0-3, LAU, cities, functional urban areas | maintained by Eurostat | `administrative_areas` | Strong default backbone for Austria and Germany. Good first shared geography layer. https://ec.europa.eu/eurostat/web/gisco |
| Destatis GV-ISys | Germany | all municipalities and admin levels | quarterly / annual tables | `administrative_areas` | Includes AGS/ARS, population, area, postal code, settlement structure. Good Germany-specific enrichment. https://www.destatis.de/EN/Themes/Countries-Regions/Regional-Statistics/OnlineListMunicipalities/list-municipalities-information-system.html |
| swisstopo swissBOUNDARIES3D | Switzerland | national, canton, district, municipality | 2026 release published 18 Dec 2025 | `administrative_areas` | Required for Swiss admin geometry because Switzerland is outside the EU GISCO core structure. https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d |
| swisstopo official index of cities and towns | Switzerland | localities with postal codes and perimeter | monthly | `administrative_areas` | Good city/place reference layer for Swiss settlements. https://opendata.swiss/en/dataset/amtliches-ortschaftenverzeichnis-mit-postleitzahl-und-perimeter |

### 2. Regional Economy And City Indicators

| Source | Coverage | Granularity | Update | Best fit | Notes |
| --- | --- | --- | --- | --- | --- |
| Eurostat regional accounts | Austria, Germany, EU-wide | NUTS regional GDP, GVA, employment | annual, typically t-2 for GDP/GVA/employment | `regional_indicator_snapshots` | Best cross-country baseline for Austria and Germany. https://ec.europa.eu/eurostat/web/national-accounts/methodology/european-accounts/regional-accounts |
| Statistik Austria Open Data | Austria | national, NUTS, regional topic tables | mirrored weekly | `regional_indicator_snapshots` | Broad official Austrian stats portal. Good for labor market, population, industry, demography. https://www.statistik.at/en/services/tools/data-access/open-data and https://data.statistik.gv.at/web_en/statistics/Economy/industry_and_construction/ |
| Statistik Austria Wirtschaftsatlas | Austria | federal states and selected business structure slices | metadata updated Aug 11, 2025 | `regional_indicator_snapshots` | Useful for sector mix and business structure by `ÖNACE`. https://www.data.gv.at/katalog/dataset/feab2273-707a-339c-a5dc-50158cf789e1 and https://www.data.gv.at/katalog/dataset/a26d78ca-e731-3773-93bc-eca6b91fa310 |
| Destatis GENESIS Open Data API | Germany | national and regional statistical tables | open API | `regional_indicator_snapshots` | Main German statistical API. Good for employment, industry, construction, prices, demographics. https://www.destatis.de/EN/Service/OpenData/api-webservice.html |
| Destatis regional statistics | Germany | municipalities and regional units | ongoing | `administrative_areas`, `regional_indicator_snapshots` | Good companion to GENESIS when we need municipality-level attributes. https://www.destatis.de/EN/Themes/Countries-Regions/Regional-Statistics/_node.html |
| Swiss FSO / BFS PX-Web and opendata.swiss | Switzerland | canton and other official statistical tables | frequent | `regional_indicator_snapshots` | Official route for Swiss population, commuting, economy, and many thematic indicators. https://opendata.swiss/en/organization/bundesamt-fur-statistik-bfs and https://www.pxweb.bfs.admin.ch/ |
| Swiss statistical atlas GDP per capita by canton | Switzerland | canton GDP per capita | latest visible dataset for 2022, data state Nov 6, 2024 | `regional_indicator_snapshots` | Useful if we need a concrete first GDP-style Swiss series fast. https://www.atlas.bfs.admin.ch/maps/13/fr/18104_8582_8581_8580/27989.html |

### 3. Strategic Sites And Industrial Facilities

| Source | Coverage | Granularity | Update | Best fit | Notes |
| --- | --- | --- | --- | --- | --- |
| European Industrial Emissions Portal | Austria, Germany, Switzerland, wider Europe | industrial site / installation | annual reporting | `strategic_sites` | Best shared regulated-facility inventory across DACH. Covers over 60,000 sites across Europe and includes Switzerland. https://industry.eea.europa.eu/industrial-emissions and https://industry.eea.europa.eu/industrial-emissions/about |
| Austrian PRTR | Austria | large industrial facilities, wastewater and waste facilities | annual | `strategic_sites` | Good Austrian facility-level environmental and industrial site signal. https://www.umweltbundesamt.at/umweltthemen/industrie/daten-industrie/prtr |
| Germany PRTR / Thru.de | Germany | industrial facilities, municipal wastewater, diffuse sources | annual with public portal updates | `strategic_sites` | Strong German site-level facility source. https://app.thru.de/ and https://www.umweltbundesamt.de/portale/thrude |
| Swiss Zefix company register | Switzerland | legal entities and addresses | daily | `strategic_sites` enrichment | Useful for operator identity resolution and address normalization, not enough on its own for plant geometry. https://opendata.swiss/en/dataset/zefix-zentraler-firmenindex |

### 4. Power, Grid, Generation, And Cross-Border Energy

| Source | Coverage | Granularity | Update | Best fit | Notes |
| --- | --- | --- | --- | --- | --- |
| APG transparency data | Austria | load, generation by type, transmission context | continuous / operational | `regional_indicator_snapshots`, energy summaries | Best Austrian transmission-level operating data. https://markt.apg.at/transparenz/last/ and https://markt.apg.at/transparenz/erzeugung/erzeugung-pro-produktionstyp/ |
| E-Control Anlagenregister | Austria | generation plant registry | public download | `power_assets` or enriched `power_plants` | Strong Austrian plant-level source for registered generation assets. https://www.e-control.at/anlagenregister |
| E-Control electricity statistics | Austria | generation fleet, installed capacity, market and grid stats | regular official statistics | `regional_indicator_snapshots`, `power_assets` | Useful for time series and annual fleet composition. https://www.e-control.at/statistik/e-statistik and https://www.e-control.at/statistik/e-statistik/archiv/bestandsstatistik |
| Bundesnetzagentur MaStR | Germany | public register of electricity and gas market units | public portal, exports, web service | `power_assets` | Best German source for plant-level power assets. https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Monitoringberichte/Marktstammdatenregister/start.html |
| Bundesnetzagentur Kraftwerksliste | Germany | individual power plants and capacity summary | published CSV/XLSX | `power_assets` | Easier first ingest than full MaStR for conventional plants and larger assets. https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Versorgungssicherheit/Erzeugungskapazitaeten/Kraftwerksliste/start.html?gtp=861646_list%253D3&r=1 |
| Swiss electricity production plants | Switzerland | plant-level electricity production assets | monthly | `power_assets` | Excellent official Swiss plant inventory with CSV and geodata endpoints. https://opendata.swiss/en/dataset/elektrizitatsproduktionsanlagen |
| Swissgrid grid data | Switzerland | production, consumption, imports, exports, transmission | continuous / monthly downloadable views | `regional_indicator_snapshots`, cross-border energy summaries | Best Swiss operational grid picture. https://www.swissgrid.ch/en/home/operation/grid-data/generation.html and https://www.swissgrid.ch/en/home/operation/grid-data/transmission.html |
| Swiss Federal Office of Energy electricity statistics | Switzerland | weekly and annual electricity balance | weekly / annual | `regional_indicator_snapshots` | Useful for historical Swiss energy balance and production/consumption series. https://www.bfe.admin.ch/bfe/en/home/supply/statistics-and-geodata/energy-statistics/electricity-statistics.html |
| ENTSO-E Transparency Platform | Austria, Germany, Switzerland, Europe | generation, load, transmission, balancing | operational | cross-border energy layer | Best shared source for cross-border electricity context. Likely useful after national sources are wired up. https://www.entsoe.eu/data/transparency-platform/ |

### 5. Politics, Legislation, Elections, Votes

| Source | Coverage | Granularity | Update | Best fit | Notes |
| --- | --- | --- | --- | --- | --- |
| Austrian Parliament Open Data | Austria | MPs, proposals, resolutions, committees, plenary materials, correspondence | active JSON API, 25 datasets | `political_event_snapshots` | Best Austrian legislative source. https://www.parlament.gv.at/opendata and https://www.parlament.gv.at/recherchieren/open-data/daten-und-lizenz/index.html |
| German Bundestag Open Data | Germany | plenary records, printed matters, MPs, roll-call vote lists, documentation API | updated on Bundestag site, page states status Mar 1 2026 | `political_event_snapshots` | Best federal German parliamentary source. https://www.bundestag.de/services/opendata/ |
| Swiss Parliament web services | Switzerland | sessions, affairs, parliamentary activity | JSON / XML web services | `political_event_snapshots` | Existing open service is older but still live and machine-readable. https://ws-old.parlament.ch/ and https://www.parlament.ch/fr/%C3%BCber-das-parlament/faits-donnees-chifrees/open-data-web-services |
| Austria National Council election pages | Austria | election result pages and historical series | official public publication | election overlays | Good official result history, but less obviously API-first than Germany/Switzerland. https://www.bmi.gv.at/412/Nationalratswahlen/ |
| Federal Returning Officer open data | Germany | Bundestag election CSV/XML, down to constituency and precinct files | official open data | election overlays | Strong machine-readable election source. https://www.bundeswahlleiterin.de/bundestagswahlen/2025/ergebnisse/opendata.html |
| Swiss federal popular votes open data | Switzerland | proposal-level real-time and historical vote JSON | updated on vote days and maintained historically | election / referendum overlays | Strong federal direct-democracy signal. https://opendata.swiss/en/dataset/echtzeitdaten-am-abstimmungstag-zu-eidgenoessischen-abstimmungsvorlagen and https://www.admin.ch/en/popular-votes |

## How This Maps To The Current Globe

The current DACH preset is mostly a curated bundle of already-existing layers. The practical question is therefore not only "what data exists?" but also "which sources can enrich the current layer stack without forcing a new DACH-only product path?"

| Current layer or module | Current implementation | Best DACH enrichment | Target model |
| --- | --- | --- | --- |
| `cities` | Natural Earth populated places and urban areas fetched directly in the browser | Eurostat GISCO cities and functional urban areas for Austria and Germany, plus Swiss locality and boundary datasets for Switzerland | `administrative_areas` |
| `powerPlants` | global WRI CSV imported into `PowerPlant` | E-Control Anlagenregister, Bundesnetzagentur Kraftwerksliste or MaStR, Swiss electricity production plants | extend `PowerPlant` now, migrate to `power_assets` later if needed |
| `commoditySites` | static JSON catalog of strategic sites | Industrial Emissions Portal base layer, Austrian PRTR, German Thru.de, curated Swiss operator / facility additions | `strategic_sites` |
| DACH economy cards | currently no real regional economic layer | Eurostat regional accounts, Statistik Austria, Destatis GENESIS, Swiss FSO / BFS PX-Web | `regional_indicator_snapshots` |
| DACH political / policy cards | currently no dedicated region-level political module | Austrian Parliament, Bundestag open data, Swiss Parliament web services, election and referendum feeds | `political_event_snapshots` |
| `financial` | currently broad global market and commodity context | keep current market overlays, but add DACH regional indicators as the real economic signal | `regional_indicator_snapshots` |
| `news` | generic multi-source global news feed | keep the generic feed, but optionally prioritize DACH publishers and merge with parliamentary / election events | existing news models plus `political_event_snapshots` |
| `outages` | internet outage feed | keep as contextual signal; it is not a priority enrichment path for a DACH economic profile | existing outage models |
| `cameras` | webcam feed | keep as secondary verification context near strategic sites and transport corridors | existing camera models |

## Lowest-Friction Datasets

These are the datasets most likely to produce visible DACH improvements quickly without forcing major architecture changes first.

1. `powerPlants`
- Bundesnetzagentur Kraftwerksliste is the easiest German plant-level ingest because it ships as a maintained CSV/XLSX publication rather than requiring a full MaStR integration.
- Swiss electricity production plants are already published as an official open dataset and fit the current point-layer pattern well.
- E-Control Anlagenregister gives Austria a clean official plant registry and is a much better DACH fit than continuing to rely on the WRI global CSV alone.

2. `commoditySites`
- The Industrial Emissions Portal is the best shared backbone for a first DACH strategic-site layer because it already spans Austria, Germany, and Switzerland under one reporting regime.
- Austrian PRTR and German Thru.de can add deeper local detail without changing the site model.
- Switzerland will likely need a more curated approach for plant identity, using Swiss operator datasets and selective manual additions.

3. DACH economy summaries
- Eurostat regional accounts are the fastest way to get comparable GDP, GVA, and employment across Austria and Germany.
- Swiss canton-level series will need Swiss FSO / BFS tables, but that still fits the same `regional_indicator_snapshots` contract.
- This data belongs in summary cards first, not as a dense point layer.

4. `cities`
- Replacing Natural Earth with an official DACH geography spine is worth doing early because it improves every later indicator join.
- GISCO plus Swiss boundary and locality data gives us a stable path for states, cantons, districts, municipalities, and city labels.

5. politics and elections
- Austrian Parliament, Bundestag, and Swiss Parliament data are all machine-readable enough to support a DACH policy timeline.
- This should ship as cards, timelines, and event overlays, not as a raw map dump of legislative records.

## Best First Ingests

If the goal is a serious DACH economic profile quickly, the best first wave is:

1. `administrative_areas`
- Eurostat GISCO for Austria and Germany
- swisstopo swissBOUNDARIES3D for Switzerland
- Destatis GV-ISys and Swiss locality index as enrichment

2. `regional_indicator_snapshots`
- Eurostat regional accounts
- Statistik Austria open data
- Destatis GENESIS
- Swiss FSO / BFS PX-Web

3. `power_assets`
- E-Control Anlagenregister
- Bundesnetzagentur Kraftwerksliste or MaStR
- Swiss electricity production plants

4. `strategic_sites`
- Industrial Emissions Portal as the shared DACH base
- Austrian PRTR and German Thru.de for country-specific detail

5. `political_event_snapshots`
- Austrian Parliament Open Data
- Bundestag Open Data
- Swiss Parliament web services

## Recommended Build Order

### Phase 1

- administrative boundaries and identifiers
- regional indicator snapshots
- DACH summary cards for GDP, employment, population, sector mix

### Phase 2

- power asset layer
- generation / load summaries
- cross-border energy view

### Phase 3

- strategic industrial sites
- industrial emissions and facility overlays
- operator entity resolution

### Phase 4

- parliamentary and election data
- policy and legislative timelines
- region-level political risk and policy change summaries

## Practical Caveats

- Eurostat gives a clean shared baseline for Austria and Germany, but not Switzerland. Swiss geography and indicators will need separate Swiss official sources.
- Eurostat GISCO boundary downloads come with specific EuroGeographics attribution and non-commercial-use conditions unless a separate commercial arrangement exists. Validate licence fit before using GISCO as a production geometry backbone.
- Factory data will remain mixed-source. The right target is a curated `strategic_sites` model, not a perfect census of every plant.
- Austria has stronger official energy and parliamentary interfaces than official factory-site inventories.
- Germany has excellent power and parliamentary data, but industrial site identity is better via PRTR than via a clean single company-site register.
- Switzerland has strong geodata and plant data, but some political and economic interfaces are distributed across multiple official portals.
- The Swiss Parliament web service is still live and explicitly available "until further notice", but the parliament has already signaled a future replacement with a newer API.
- The Industrial Emissions Portal notes incomplete recent submissions for Switzerland for reporting years 2023 and 2024, so Swiss facility coverage should be validated against local sources before it is treated as complete.

## Source Links

- Eurostat GISCO: https://ec.europa.eu/eurostat/web/gisco
- Eurostat regional accounts: https://ec.europa.eu/eurostat/web/national-accounts/methodology/european-accounts/regional-accounts
- Statistik Austria open data: https://www.statistik.at/en/services/tools/data-access/open-data
- Statistik Austria catalog: https://data.statistik.gv.at/web/catalog.jsp
- Austria Wirtschaftsatlas, federal states: https://www.data.gv.at/katalog/dataset/feab2273-707a-339c-a5dc-50158cf789e1
- Austria Wirtschaftsatlas, employee size classes: https://www.data.gv.at/katalog/dataset/a26d78ca-e731-3773-93bc-eca6b91fa310
- Austrian Parliament open data: https://www.parlament.gv.at/opendata
- APG transparency: https://markt.apg.at/transparenz/last/
- APG generation by type: https://markt.apg.at/transparenz/erzeugung/erzeugung-pro-produktionstyp/
- E-Control Anlagenregister: https://www.e-control.at/anlagenregister
- E-Control electricity statistics: https://www.e-control.at/statistik/e-statistik
- Austrian PRTR: https://www.umweltbundesamt.at/umweltthemen/industrie/daten-industrie/prtr
- Destatis GENESIS API: https://www.destatis.de/EN/Service/OpenData/api-webservice.html
- Destatis regional statistics: https://www.destatis.de/EN/Themes/Countries-Regions/Regional-Statistics/_node.html
- Destatis GV-ISys: https://www.destatis.de/EN/Themes/Countries-Regions/Regional-Statistics/OnlineListMunicipalities/list-municipalities-information-system.html
- Bundestag open data: https://www.bundestag.de/services/opendata/
- Bundeswahlleiterin open data: https://www.bundeswahlleiterin.de/bundestagswahlen/2025/ergebnisse/opendata.html
- Bundesnetzagentur MaStR: https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Monitoringberichte/Marktstammdatenregister/start.html
- Bundesnetzagentur Kraftwerksliste: https://www.bundesnetzagentur.de/DE/Fachthemen/ElektrizitaetundGas/Versorgungssicherheit/Erzeugungskapazitaeten/Kraftwerksliste/start.html?gtp=861646_list%253D3&r=1
- German PRTR portal: https://app.thru.de/
- Umweltbundesamt Thru.de portal page: https://www.umweltbundesamt.de/portale/thrude
- Industrial Emissions Portal: https://industry.eea.europa.eu/industrial-emissions
- Swiss opendata portal: https://opendata.swiss/en
- Swiss FSO organization: https://opendata.swiss/en/organization/bundesamt-fur-statistik-bfs
- Swiss Parliament web services: https://ws-old.parlament.ch/
- Swiss Parliament open data page: https://www.parlament.ch/fr/%C3%BCber-das-parlament/faits-donnees-chifrees/open-data-web-services
- swissBOUNDARIES3D: https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d
- Swiss locality index: https://opendata.swiss/en/dataset/amtliches-ortschaftenverzeichnis-mit-postleitzahl-und-perimeter
- Swiss electricity production plants: https://opendata.swiss/en/dataset/elektrizitatsproduktionsanlagen
- Swissgrid generation data: https://www.swissgrid.ch/en/home/operation/grid-data/generation.html
- Swissgrid transmission data: https://www.swissgrid.ch/en/home/operation/grid-data/transmission.html
- Swiss electricity statistics: https://www.bfe.admin.ch/bfe/en/home/supply/statistics-and-geodata/energy-statistics/electricity-statistics.html
- Swiss popular votes open data: https://opendata.swiss/en/dataset/echtzeitdaten-am-abstimmungstag-zu-eidgenoessischen-abstimmungsvorlagen
- Swiss popular votes page: https://www.admin.ch/en/popular-votes
- Swiss Zefix company register: https://opendata.swiss/en/dataset/zefix-zentraler-firmenindex
- ENTSO-E Transparency Platform: https://www.entsoe.eu/data/transparency-platform/
