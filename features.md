# Globe Tracker — Features

## Implemented

### Aviation
- Flights — OpenSky + ADSB.lol (civilian + military, 10s polling)
- Airports — OurAirports (6,145 large/medium/military globally)
- NOTAMs — FAA TFRs + hardcoded no-fly zones + OpenAIP (restricted airspace)
- Flight trails — RDP simplification + Catmull-Rom spline smoothing

### Maritime
- Ships — AIS WebSocket stream (real-time)
- Ship trails
- Submarine cables — TeleGeography GeoJSON

### Space
- Satellites — CelesTrak TLEs (12 categories, orbits, footprints, heatmap, pass prediction)

### Rail
- Trains — HAFAS European rail with position interpolation + speed estimation

### Geopolitical & Events
- Earthquakes — USGS real-time (ShakeMap MMI attenuation + infrastructure impact)
- Natural events — NASA EONET (wildfires, volcanoes, storms, floods, ice)
- Conflict events — ACLED + UCDP
- News — GDELT + WorldNewsAPI + Mediastack + GNews + Hacker News + Currents + TheNewsAPI (7 sources, cross-source dedup, temporal weighting, category chips, trending keywords)
- GPS jamming — GPSJam
- Fire hotspots — NASA FIRMS

### Infrastructure
- Power plants — Global Power Plant Database
- Internet outages — Cloudflare Radar
- Internet traffic — Cloudflare Radar (traffic arcs + attack data)
- Webcams — Windy + NYC DOT + YouTube Live + ASFINAG + Autobahn.de + Viasuisse

### Geography & UX
- Country borders + selection/filtering + convex hull (international waters)
- Cities with population data
- 3D terrain + buildings
- Timeline / playback with frame interpolation (up to 7 days)
- Deep links (full state in URL hash)
- Quick bar, sidebar, right panel (tabbed feeds)
- Workspaces (save/restore named configurations)
- Selection tray (multi-entity comparison)
- Mobile-responsive bottom-sheet
- Admin dashboard with global poller
- Cross-layer analytics (earthquake→cable→plant, GPS jamming→flights, fire→infrastructure)
- Financial/commodity data overlay
- Watchlists & alerts (bell icon)

---

## Future Ideas

### Weather & Climate
- OpenWeatherMap — real-time stations, severe alerts, wind/temp overlays
- Open-Meteo — free, global forecasts, marine weather
- NOAA Storm Reports — tornadoes, hail, wind with coordinates

### Space & Astronomy
- NASA NEO — asteroid close approaches with distance/velocity
- Solar flare / geomagnetic storm data — aurora probability overlays

### Maritime extras
- NOAA buoys — ocean weather buoys
- Radiosondes (IGRA) — weather balloon launch sites

### Network & Cyber
- Tor relay map — public node locations (Onionoo API)
- Internet Exchange Points — PeeringDB
- Cell tower coverage — OpenCelliD (43M+ towers)

### Environmental
- OpenAQ — air quality stations worldwide
- Copernicus Marine — ocean currents, sea surface temp

### Other
- Space Launches — Launch Library 2
- ISS Live Feed — NASA stream when ISS selected
- Space Debris — CelesTrak debris TLEs
- Lightning Strikes — Blitzortung real-time
- Radio Stations — Radio Garden
- Geolocated Live Streams
