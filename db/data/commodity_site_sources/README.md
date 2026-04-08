# Commodity Site Sources

This directory is the offline import staging area for `db/data/commodity_sites.json`.

Rules:

- Do not fetch third-party source data at request time.
- Prefer reviewed snapshots from official operator, government, or authority sources.
- Normalize each source into either:
  - `normalized_json`
  - `normalized_csv`
- Rebuild the public snapshot with:

```bash
bin/rails commodity_sites:rebuild
```

Current source groups:

- `energy_operator_sites.json`
  - LNG, gas-processing, crude and refining sites from operator snapshots
- `metals_operator_sites.json`
  - copper and iron ore flagship operations from operator snapshots
- `metals_expansion_sites.json`
  - additional copper and iron ore sites from operator snapshots
- `fertilizer_official_sites.json`
  - ammonia, urea, and phosphate fertilizer complexes from official operator sources
- `specialty_operator_sites.json`
  - helium and fertilizer strategic sites from official / authority sources

Required normalized fields:

- `id`
- `name`
- `commodity_key`
- `commodity_name`
- `site_kind`
- `stage`
- `country_code`
- `country_name`
- `location_label`
- `lat`
- `lng`
- `source_name`
- `source_url`
- `source_kind`

Recommended optional fields:

- `map_label`
- `location_precision`
- `operator`
- `products`
- `summary`
- `source_dataset`
