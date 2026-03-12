# Globe Tracker — Features

## Implemented

### Flights (OpenSky Network)
- Live flights with position interpolation, callsign labels
- Flight trails, airline filtering (ICAO codes), military detection
- Airline name lookup (~80 major airlines)

### Satellites (CelesTrak TLEs)
- 12 categories: ISS/Stations, Starlink, GPS, Weather, Earth Resources, Science, Military, Geostationary, Iridium, OneWeb, Planet Labs, Spire
- Orbit trails, hex footprint (0.12° grid), coverage heatmap, build heatmap on countries

### Maritime (AIS)
- Live vessel positions with ship type icons

### Geography
- Cities with population data, country borders
- Country selection (click or draw circle), filtering by region

### Events
- **Earthquakes** — USGS real-time feed (M2.5+ last 24h), magnitude-colored markers with impact rings, detail panel with depth/magnitude/alert
- **Natural Events** — NASA EONET (wildfires, volcanoes, storms, floods, ice, etc.), category-colored markers with event trails, source links
- **Live Cameras** — Windy Webcams API (70k+ worldwide), NYC DOT, YouTube Live, ASFINAG (AT), Autobahn.de (DE), Viasuisse (CH); viewport-aware loading, clustering, camera sidebar panel, auto-refresh preview, re-fetches on camera move

### Infrastructure
- Collapsible sidebar with organized sections
- Stats bar (flights, satellites, ships, events, UTC clock)
- Search across all entity types
- User preferences (camera, layers, countries, airline filter) saved to DB
- Hot reload in development (hotwire-livereload)

---

## In Progress

### NOTAMs / No-Fly Zones
- FAA NOTAM API for TFR polygons on the globe
- Highlight flights routing around restricted airspace
- Show flight density drops in conflict/restricted regions

### Cyber Attacks → Target Infrastructure
- Attack target countries → highlight their power plants, cables, data centers
- Attack origin overlaid with internet traffic share
- Visual link between attack arcs and affected infrastructure

### Satellite to Ground Events
- Show which imaging/comms satellites have line-of-sight to a selected event
- Satellite coverage footprint over active events (earthquakes, conflicts)
- Starlink/OneWeb coverage gaps overlaid with internet outages

---

## Planned — Cross-Layer Correlations

### GPS Jamming → Flights & Ships
- Flights/ships entering jamming zones highlighted (red outline, warning)
- "Affected count" on jamming markers
- ADS-B NACP accuracy degradation near jamming zones

### Submarine Cables → Internet Outages
- Outage occurs → highlight nearby cables as potential cause
- Cable cut events correlated with ship positions near cable routes

### Earthquakes → Infrastructure
- Shake radius overlay on power plants, cable landing points, airports
- "At risk" infrastructure count per quake
- Post-quake outage correlation

### Country Borders → News
- Auto-fetch and display news events when a country is selected

---

## Camera Sources

### Active
- **Windy Webcams API** — 70k+ webcams worldwide, periodic image updates (~30s), free tier with API key
- **NYC DOT** — ~800 NYC traffic cameras, live image feed, no key needed
- **YouTube Live** — location-based live stream search, embeddable video, requires API key (quota limited)

### To Add — European Traffic Cameras
- **ASFINAG** (Austria) — `https://www.asfinag.at/verkehr/verkehrskameras/` — Austrian highway cameras, JSON API, hundreds of cams across the Autobahn network
- **Autobahn.de** (Germany) — `https://verkehr.autobahn.de/o/autobahn/` — Official German federal highway REST API with webcams endpoint, free, no key needed
- **Viasuisse / ASTRA** (Switzerland) — Swiss national road traffic cameras, public feeds

### To Add — US Traffic Cameras (DOT)
- **Caltrans CCTV** (California) — `https://cwwp2.dot.ca.gov/data/d{n}/cctv/cctvStatusLog.json` — thousands of highway cams across 12 districts
- **WSDOT** (Washington) — `https://data.wsdot.wa.gov/log/camera/cameras.json` — ~1,000 cams
- **PennDOT** (Pennsylvania) — `https://www.511pa.com/api/cameras`
- **TxDOT** (Texas) — `https://its.txdot.gov/` — JSON feed
- **511 systems** — many states (Florida, Virginia, Colorado, etc.) have 511 APIs with camera endpoints

### To Add — Global
- **Skyline Webcams** — tourism and city cams, embeddable players
- **EarthCam** — landmark cams worldwide (Times Square, Abbey Road, etc.)

### Not Adding
- **Insecam** — large aggregator of publicly accessible IP cameras. Not adding because these are unsecured cameras whose owners likely don't know they're being indexed. Ethically questionable — the cameras are "public" only because they lack authentication, not because the owners intended them to be broadcast. Using this source would mean profiting from poor security practices.

---

## Planned — New Data Sources

### NASA FIRMS (Active Fires)
- Real-time fire/hotspot locations
- Correlate with natural events + air quality

### OpenAQ (Air Quality)
- Air quality stations worldwide
- Overlay with fires, power plants

### NOAA Weather
- Severe weather alerts, hurricanes, GeoJSON overlays

### UNHCR (Refugee Flows)
- Migration routes and camps, correlate with conflict events

### IODA (Internet Outage Detection)
- Better outage detection than Cloudflare for regional outages (Georgia Tech API)

---

## Planned — Original

### GDELT Geotagged News
- Source: `api.gdeltproject.org`
- Geotagged news articles from worldwide media
- Pin headlines to locations with category coloring (conflict, politics, disaster, economy)
- Click for article summary + source link
- Rate limits: generous, no key needed

### Space Launches
- Source: `ll.thespacedevs.com` (Launch Library 2)
- Upcoming and recent launches pinned to launch pads
- Countdown timers, rocket type, mission details
- Rate limits: 300 requests/day, no key needed

### Trains (Real-Time)
- Digitraffic Finland: `rata.digitraffic.fi/api/v1` — Finnish rail network, free
- Amtraker: `api.amtraker.com` — US Amtrak trains, free

### Weather Overlay
- OpenWeatherMap tile layers for temperature, precipitation, wind
- Storm tracking integration with EONET severe storms

### ISS Live Feed
- Embed NASA ISS live stream when ISS satellite is selected
- Crew information overlay

### Submarine Cables
- TeleGeography submarine cable GeoJSON (static dataset)
- Cable lines on ocean floor with landing points

### Space Debris
- CelesTrak catalogued debris TLEs
- Dot cloud of tracked debris objects

### Asteroid Close Approaches
- NASA NEO API (free, key required)
- Markers for upcoming close approaches with distance and size

### Internet Outages
- Cloudflare Radar or IODA
- Country/region highlights showing connectivity drops

### Lightning Strikes
- Blitzortung real-time lightning network
- Flash animations at strike locations

### Radio Stations
- Radio Garden or similar
- Radio icons on globe, click to play live audio

### Geolocated Live Streams
- Twitch / YouTube geotagged streams
- Stream icons on globe, click to open embed
