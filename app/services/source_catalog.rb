class SourceCatalog
  class << self
    def entries
      [
        { icon: "fa-solid fa-plane",            title: "ADS-B Exchange",        status: "LIVE",       status_class: "live",       link: "https://api.adsb.lol" },
        { icon: "fa-solid fa-tower-broadcast",  title: "OpenSky Network",       status: "API",        link: "https://opensky-network.org" },
        { icon: "fa-solid fa-ship",             title: "AIS Stream",            status: "LIVE",       status_class: "live",       link: "https://aisstream.io" },
        { icon: "fa-solid fa-satellite",        title: "CelesTrak",             status: "API",        link: "https://celestrak.org" },
        { icon: "fa-solid fa-house-crack",      title: "USGS Earthquakes",      status: "LIVE",       status_class: "live",       link: "https://earthquake.usgs.gov" },
        { icon: "fa-solid fa-fire",             title: "NASA FIRMS",            status: "API",        link: "https://firms.modaps.eosdis.nasa.gov" },
        { icon: "fa-solid fa-newspaper",        title: "GDELT Project",         status: "LIVE",       status_class: "live",       link: "https://gdeltproject.org" },
        { icon: "fa-solid fa-rss",              title: "Curated RSS Mesh",      status: "ACTIVE",     status_class: "live" },
        { icon: "fa-solid fa-rss",              title: "Legacy Reuters RSS",    status: "DEPRECATED", status_class: "deprecated", link: "https://feeds.reuters.com/reuters/worldNews" },
        { icon: "fa-solid fa-rss",              title: "Multi-source News APIs",status: "ACTIVE",     status_class: "live" },
        { icon: "fa-solid fa-hand-holding-heart", title: "ReliefWeb",           status: "PENDING",    status_class: "pending",    link: "https://apidoc.reliefweb.int/" },
        { icon: "fa-solid fa-diagram-project",  title: "Media Cloud",           status: "PENDING",    status_class: "pending",    link: "https://www.mediacloud.org/documentation" },
        { icon: "fa-solid fa-satellite-dish",   title: "GPS Interference",      status: "DERIVED",    status_class: "computed",   link: "https://gpsjam.org" },
        { icon: "fa-solid fa-crosshairs",       title: "UCDP Conflicts",        status: "API",        link: "https://ucdp.uu.se" },
        { icon: "fa-solid fa-cloud",            title: "Cloudflare Radar",      status: "LIVE",       status_class: "live",       link: "https://radar.cloudflare.com" },
        { icon: "fa-solid fa-network-wired",    title: "TeleGeography",         status: "FREE",       status_class: "free",       link: "https://submarinecablemap.com" },
        { icon: "fa-solid fa-wifi",             title: "IODA Outages",          status: "FREE",       status_class: "free",       link: "https://ioda.inetintel.cc.gatech.edu" },
        { icon: "fa-solid fa-bolt",             title: "NASA EONET",            status: "API",        link: "https://eonet.gsfc.nasa.gov" },
        { icon: "fa-solid fa-video",            title: "Windy Webcams",         status: "API",        link: "https://api.windy.com/webcams" },
        { icon: "fa-brands fa-youtube",         title: "YouTube Live",          status: "LIVE",       status_class: "live",       link: "https://developers.google.com/youtube/v3" },
        { icon: "fa-solid fa-traffic-light",    title: "NYC Traffic Cams",      status: "LIVE",       status_class: "live",       link: "https://webcams.nyctmc.org" },
        { icon: "fa-solid fa-globe",            title: "Cesium Ion",            status: "ENGINE",     link: "https://cesium.com" },
        { icon: "fa-solid fa-building",         title: "Google 3D Tiles",       status: "ENGINE",     link: "https://cesium.com/platform/cesium-ion/content/google-photorealistic-3d-tiles/" },
        { icon: "fa-solid fa-map",              title: "Natural Earth",         status: "FREE",       status_class: "free",       link: "https://naturalearthdata.com" },
        { icon: "fa-solid fa-user-astronaut",   title: "UCS Satellites",        status: "OSS",        status_class: "oss",        link: "https://ucsusa.org/resources/satellite-database" },
        { icon: "fa-solid fa-user-secret",      title: "Classified Sat Intel",  status: "DERIVED",    status_class: "computed" },
        { icon: "fa-solid fa-plane-lock",       title: "OpenAIP Airspace",      status: "API",        link: "https://openaip.net" },
        { icon: "fa-solid fa-plane-departure",  title: "OurAirports",           status: "OSS",        status_class: "oss",        link: "https://ourairports.com" },
        { icon: "fa-solid fa-jet-fighter",      title: "Military Classifier",   status: "DERIVED",    status_class: "computed" },
        { icon: "fa-solid fa-oil-well",         title: "Global Energy Monitor", status: "FREE",       status_class: "free",       link: "https://globalenergymonitor.org" },
        { icon: "fa-solid fa-bolt",             title: "Power Plant Database",  status: "OSS",        status_class: "oss",        link: "https://github.com/wri/global-power-plant-database" },
        { icon: "fa-solid fa-chart-line",       title: "Alpha Vantage",         status: "API",        link: "https://alphavantage.co" },
        { icon: "fa-solid fa-coins",            title: "European Central Bank", status: "FREE",       status_class: "free",       link: "https://ecb.europa.eu" },
      ]
    end
  end
end
