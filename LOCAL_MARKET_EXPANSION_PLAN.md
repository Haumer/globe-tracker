# Local Market Expansion Plan

## Goal

Turn the current commodity-only financial layer into a broader market signal system that can support:

- strategic commodities and FX on the globe
- benchmark watchlists for non-spatial instruments
- market-aware cross-layer insights

## Phase 1

1. Respect the intended refresh cadence for market polling.
2. Expand the stored quote categories beyond `commodity` and `currency`.
3. Add an initial benchmark watchlist:
   - US large caps
   - Nasdaq growth proxy
   - Bitcoin
   - Ether
   - US 2Y Treasury yield
   - US 10Y Treasury yield
   - Federal funds rate
4. Keep non-spatial benchmarks out of the globe marker layer.
5. Expose watchlist-style benchmark data from the API for future UI work.
6. Add initial market-aware insights:
   - chokepoint market stress
   - outage + currency stress

## Phase 2

1. Add a dedicated market watchlist UI instead of forcing global benchmarks onto the globe.
2. Add more benchmark coverage:
   - DXY
   - volatility
   - regional equity proxies
   - freight/shipping benchmarks
3. Add percentile/z-score based market anomaly scoring.
4. Add theater-to-asset mappings through the ontology so market impacts become explainable.

## Notes

- This file is intentionally local and untracked.
- The first implementation slice focuses on data plumbing and insight generation, not the full market UI.
