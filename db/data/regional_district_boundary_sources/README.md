# Regional District Boundary Sources

This directory stores source-backed district or district-equivalent boundary snapshots for regional profiles.

Rules:

- Every file here must be re-retrievable from an official source.
- The retrieval path must be recorded in `manifest.json`.
- Boundaries normalize into one shared GeoJSON contract.
- Country-specific providers are allowed, but the app must not depend on country-specific models.

Current sources:

- `de_vg250_districts`
  - Provider: `BKG VG250 Kreise`
  - Coverage: Germany districts and district-free cities
  - Source page: `https://gdz.bkg.bund.de/index.php/default/open-data/wfs-verwaltungsgebiete-1-250-000-stand-01-01-wfs-vg250.html`
  - Data endpoint: `https://sgx.geodatenzentrum.de/wfs_vg250?...typeNames=vg250:vg250_krs...`

- `at_statistik_districts`
  - Provider: `Statistik Austria`
  - Coverage: Austria political districts and statutory cities
  - Source page: `https://data.statistik.gv.at/web/meta.jsp?dataset=OGDEXT_POLBEZ_1`
  - Data endpoint: `https://www.statistik.at/gs-open/GEODATA/ows?...typeName=GEODATA:STATISTIK_AUSTRIA_POLBEZ_20250101...`

- `ch_geo_admin_districts`
  - Provider: `swisstopo / geo.admin.ch`
  - Coverage: Switzerland district boundaries plus canton-equivalent polygons for single-district cantons
  - Source page: `https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d`
  - Catalog: `https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d`
  - Data endpoint: `https://api3.geo.admin.ch/rest/services/ech/MapServer/identify`
