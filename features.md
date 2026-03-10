# Globe Tracker — Future Data Layers

## Transportation

### Ships / Maritime (Priority: HIGH)
- **API:** MarineTraffic or AIS data feeds
- **Display:** Ship icons with vessel name, type (cargo, tanker, cruise), speed, heading
- **Update frequency:** Poll every 30 seconds
- **Rails backend:** `GET /api/ships`

### Space Launches (Priority: LOW)
- **API:** RocketLaunch.Live or Launch Library 2 API
- **Display:** Launch site markers with countdown timers, trajectory lines for active launches
- **Rails backend:** `GET /api/launches`

### Air Traffic Control Zones (Priority: LOW)
- **Display:** ARTCC/FIR boundary polygons overlaid on the globe
- **Data:** Static GeoJSON boundaries, loaded once

## Weather & Environment

### Earthquakes (Priority: HIGH)
- **API:** USGS Earthquake Hazards API (free, no auth required)
- **Endpoint:** `https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson`
- **Display:** Pulsing circles sized by magnitude, colored by depth
- **Update frequency:** Poll every 60 seconds
- **Rails backend:** `GET /api/earthquakes`

### Volcanoes (Priority: MEDIUM)
- **API:** Smithsonian Global Volcanism Program (GVP)
- **Display:** Volcano markers with eruption status (active, warning, dormant)
- **Data:** Refreshed daily
- **Rails backend:** `GET /api/volcanoes`

### Wildfires (Priority: MEDIUM)
- **API:** NASA FIRMS (Fire Information for Resource Management System), free
- **Display:** Fire hotspot clusters with intensity coloring
- **Update frequency:** Every 15 minutes
- **Rails backend:** `GET /api/wildfires`

### Storms / Hurricanes (Priority: MEDIUM)
- **API:** NOAA National Hurricane Center / IBTrACS
- **Display:** Storm tracks with forecast cones, wind speed rings
- **Rails backend:** `GET /api/storms`

### Lightning Strikes (Priority: LOW)
- **API:** Blitzortung or similar real-time lightning network
- **Display:** Flash animations at strike locations
- **Update frequency:** Real-time via WebSocket if available
- **Rails backend:** `GET /api/lightning`

### Ocean Currents & Sea Temperature (Priority: LOW)
- **API:** NOAA / Copernicus Marine Service
- **Display:** Animated flow lines for currents, heatmap for sea surface temperature
- **Rails backend:** `GET /api/ocean`

## Space

### Space Debris (Priority: MEDIUM)
- **API:** CelesTrak catalogued debris TLEs
- **Display:** Dot cloud of tracked debris objects, computed client-side like satellites
- **Rails backend:** `GET /api/debris`

### Asteroid Close Approaches (Priority: LOW)
- **API:** NASA NEO (Near Earth Object) API (free, key required)
- **Display:** Markers for upcoming close approaches with distance and size info
- **Rails backend:** `GET /api/asteroids`

### ISS Live Camera (Priority: LOW)
- **Display:** Clickable ISS icon that opens the live NASA stream
- **Data:** ISS position already available from satellite TLEs

## Infrastructure & Connectivity

### Submarine Cables (Priority: MEDIUM)
- **Data:** TeleGeography submarine cable GeoJSON (static dataset)
- **Display:** Cable lines on the ocean floor with landing points, click for cable details
- **Rails backend:** `GET /api/cables`

### Internet Outages (Priority: LOW)
- **API:** Cloudflare Radar or IODA (Internet Outage Detection and Analysis)
- **Display:** Country/region highlights showing connectivity drops
- **Rails backend:** `GET /api/outages`

### Power Grid / Blackouts (Priority: LOW)
- **API:** Publicly available grid status feeds (varies by region)
- **Display:** Regional overlay showing grid stress or outage areas
- **Rails backend:** `GET /api/power`

## Social / Activity

### Live Streams (Priority: LOW)
- **API:** Twitch / YouTube geotagged live streams
- **Display:** Stream icons on globe, click to open embed
- **Rails backend:** `GET /api/streams`

### Geolocated News (Priority: LOW)
- **API:** GDELT Project or MediaStack
- **Display:** News event markers clustered by region, click for headlines
- **Rails backend:** `GET /api/news`

### Radio Stations (Priority: LOW)
- **API:** Radio Garden or similar
- **Display:** Radio icons on globe, click to play live audio stream
- **Rails backend:** `GET /api/radio`
