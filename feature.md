# Feature Ideas — Future Data Layers

## Weather & Climate
- **OpenWeatherMap** — real-time weather stations, severe weather alerts, wind/temp overlays (free tier: 1000 calls/day)
- **Open-Meteo** — fully free, no key needed. Global forecasts, historical data, marine weather
- **NOAA Storm Reports** — severe weather events (tornadoes, hail, wind) with coordinates

## Space & Astronomy
- **NASA NEO (Near Earth Objects)** — asteroid close approaches with distance/velocity (free API)
- **Solar flare / geomagnetic storm data** — NOAA SWPC, aurora probability zone overlays

## Maritime & Aviation extras
- **NOAA buoys** — ocean weather buoys with real-time wave/wind/temp data
- **Radiosondes (IGRA)** — weather balloon launch sites and soundings
- **Volcanoes (Smithsonian GVP)** — active volcano locations + eruption alerts via USGS

## Network & Cyber
- **Shodan** — exposed devices/services geolocated (limited free tier)
- **Tor relay map** — public Tor node locations (free via Onionoo API)
- **Internet Exchange Points** — PeeringDB, free API, IXP locations worldwide
- **Cell tower coverage** — OpenCelliD bulk CSV, 43M+ towers globally with radio type (2G/3G/4G/5G) and coverage radius. Color by radio type, filter by country/MCC. Downsample for performance.

## Environmental
- **OpenAQ** — real-time air quality from 10k+ stations worldwide (free)
- **NASA FIRMS (fire hotspots)** — active fires updated every few hours, very visual
- **Copernicus Marine** — ocean currents, sea surface temp (free with registration)

---

# Already Implemented

## Aviation
- ~~Flights — OpenSky + ADSB.lol (civilian + military, 10s polling)~~
- ~~Airports — OurAirports (6,145 large/medium/military globally)~~
- ~~NOTAMs — FAA TFRs + hardcoded no-fly zones + OpenAIP (restricted airspace)~~
- ~~Flight trails — RDP simplification + Catmull-Rom spline smoothing~~

## Maritime
- ~~Ships — AIS WebSocket stream (real-time)~~
- ~~Ship trails~~
- ~~Submarine cables~~

## Space
- ~~Satellites — CelesTrak TLEs (orbits, footprints, heatmap, category filters)~~

## Geopolitical & Events
- ~~Earthquakes — USGS real-time~~
- ~~Natural events — NASA EONET~~
- ~~Conflict events — ACLED~~
- ~~News — GDELT + WorldNewsAPI + Mediastack + GNews + Hacker News + Currents + TheNewsAPI (6 sources, cross-source dedup)~~
- ~~GPS jamming~~

## Infrastructure
- ~~Power plants — Global Power Plant Database~~
- ~~Internet outages — Cloudflare Radar~~
- ~~Internet traffic — Cloudflare Radar (traffic arcs + attack data)~~
- ~~Webcams~~

## Map & Visualization
- ~~Country borders + selection/filtering~~
- ~~Cities~~
- ~~3D terrain + buildings~~
- ~~Unified timeline / playback with frame interpolation~~
- ~~Convex hull filtering (international waters between selected countries)~~
- ~~Admin dashboard with global poller (pause/stop/start)~~
- ~~Position snapshots for playback (flight + ship, dedup with 60s threshold)~~
