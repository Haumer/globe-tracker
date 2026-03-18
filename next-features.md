# Next Features — Post-Deploy

## 1. Conflict Zone Country Highlighting

When a conflict pulse zone reaches ACTIVE (70+), highlight the associated countries using the existing border polygon infrastructure.

### Approach
- Hybrid: subtle country fill (5-8% opacity) + existing pulse circles for hotspot intensity
- At a glance: "Iran is at war" (whole country subtly lit)
- Zoom in: pulse circles show where intensity concentrates

### Implementation
- Use existing country polygon data from geography/selection layer (`_borderCountryMap`)
- Map pulse zones to countries: use `cross_layer_signals.known_conflict_zone` countries, or reverse-geocode zone centroid to country
- Color country fill by pulse score: yellow (50-69), orange (70-79), red (80+)
- Only highlight for ACTIVE/SURGING zones (don't color a country yellow for 1 incident)
- Multiple countries per conflict: Israel+Lebanon, Pakistan+Afghanistan
- Pulsing border outline for surging zones

### Data Available
- `ConflictEvent.country` field — maps conflict names to countries
- `ChokepointMonitorService::CHOKEPOINTS[].countries` — affected countries per chokepoint
- `ConflictPulseService` zones have lat/lng centroids that can be reverse-geocoded
- Border polygons already loaded in geography.js for country selection

### Files to Modify
- `app/javascript/globe/controller/infrastructure/conflictPulse.js` — add country highlighting in `_renderConflictPulse`
- `app/javascript/globe/controller/geography.js` — expose country polygon highlighting method
- `app/services/conflict_pulse_service.rb` — add `countries` field to zone output

## 2. Other Pending Improvements
- Merge nearby zones about the same conflict (Israel/Lebanon/Iran as one "Middle East War" super-zone)
- Toast notification improvements for surging zones
- Conflict timeline sparkline in detail panel
- Real-time news push via ActionCable when new articles arrive
