# City Profile Sources

This directory is the curated staging area for regional city enrichment.

Repo-wide rule:

- follow [DATA_SOURCING.md](/tmp/globe-dach-regional-profile/DATA_SOURCING.md)

Rules:

- Keep the output generic. Do not add country-specific models or schemas.
- Country-specific source packs are acceptable.
- Rank cities by strategic relevance, not population alone.
- Use ASCII by default for names and aliases in source files.
- Every source pack must be rebuildable from a documented upstream source path.
- Do not rely on one-off manual curation without recording how to regenerate the candidate set.

Current source groups:

- `austria_economic_cities.json`
  - Austria-first economic, logistics, administrative, and industrial city pack
  - base source family: Statistik Austria / data.gv.at
- `germany_strategic_cities.json`
  - Germany strategic city pack for DACH local mode
  - base source family: Destatis regional statistics
- `switzerland_strategic_cities.json`
  - Switzerland strategic city pack for DACH local mode
  - base source family: BFS / swisstopo / opendata.swiss

Required fields:

- `id`
- `name`
- `country_code`
- `country_name`
- `admin_area`
- `lat`
- `lng`
- `priority`

Recommended optional fields:

- `aliases`
- `role_tags`
- `strategic_sectors`
- `summary`

## Rebuild Standard

Each country pack should follow this pattern:

1. Base geography from a reliable official or supranational dataset
2. Administrative and economic enrichment from official statistics
3. Strategic weighting from reusable app layers such as power plants, strategic sites, airports, rail, and logistics nodes
4. Manual overrides only when the reason is recorded in the pack or an adjacent note

For DACH, the intended base sources are:

- Austria: Statistik Austria / data.gv.at and other official Austrian statistical geography sources
- Germany: Destatis regional and municipality datasets
- Switzerland: BFS / swisstopo locality and administrative datasets

Current DACH coverage in this branch:

- Austria: 32 curated city profiles
- Germany: 34 curated city profiles
- Switzerland: 18 curated city profiles

The goal is not "perfect automatic ranking." The goal is that a future rebuild can recover the same city universe and most of the same prioritization logic without starting from scratch.
