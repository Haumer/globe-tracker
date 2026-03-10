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
- **Live Cameras** — Windy Webcams API (70k+ worldwide), viewport-aware loading, thumbnail preview in detail panel, "Watch Live" link, re-fetches on camera move

### Infrastructure
- Collapsible sidebar with organized sections
- Stats bar (flights, satellites, ships, events, UTC clock)
- Search across all entity types
- User preferences (camera, layers, countries, airline filter) saved to DB
- Hot reload in development (hotwire-livereload)

---

## Planned

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
