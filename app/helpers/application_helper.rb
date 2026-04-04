module ApplicationHelper
  PRIMARY_SIDEBAR_LAYER_DEFS = [
    { key: "situations", label: "Conflict Theaters", icon: "fa-solid fa-wave-square", color: "#ff7043", target: "qlSituations" },
    { key: "insights", label: "Insights", icon: "fa-solid fa-brain", color: "#26c6da", target: "qlInsights" },
    { key: "news", label: "News", icon: "fa-solid fa-newspaper", color: "#ff9800", target: "qlNews" },
  ].freeze

  ADVANCED_SIDEBAR_LIBRARY_DEFS = [
    { key: "flights", label: "Flights", icon: "fa-solid fa-plane", color: "#4fc3f7", target: "qlFlights" },
    { key: "ships", label: "Ships", icon: "fa-solid fa-ship", color: "#26c6da", target: "qlShips" },
    { key: "satellites", label: "Satellite Categories", icon: "fa-solid fa-satellite", color: "#ab47bc", target: "qlSatellites" },
    { key: "earthquakes", label: "Earthquakes", icon: "fa-solid fa-house-crack", color: "#ff7043", target: "qlEarthquakes" },
    { key: "naturalEvents", label: "Natural Events", icon: "fa-solid fa-bolt", color: "#66bb6a", target: "qlEvents" },
    { key: "fireHotspots", label: "Fire Hotspots", icon: "fa-solid fa-fire", color: "#ff5722", target: "qlFireHotspots" },
    { key: "weather", label: "Weather", icon: "fa-solid fa-cloud-sun-rain", color: "#1e88e5", target: "qlWeather" },
    { key: "conflicts", label: "Armed Conflicts", icon: "fa-solid fa-crosshairs", color: "#f44336", target: "qlConflicts" },
    { key: "traffic", label: "Internet Traffic", icon: "fa-solid fa-globe", color: "#69f0ae", target: "qlTraffic" },
    { key: "outages", label: "Internet Outages", icon: "fa-solid fa-wifi", color: "#e040fb", target: "qlOutages" },
    { key: "gpsJamming", label: "GPS Jamming", icon: "fa-solid fa-satellite-dish", color: "#f44336", target: "qlGpsJamming" },
    { key: "chokepoints", label: "Shipping Chokepoints", icon: "fa-solid fa-anchor", color: "#4fc3f7", target: "qlChokepoints" },
    { key: "trains", label: "Live Trains", icon: "fa-solid fa-train-subway", color: "#e53935", target: "qlTrains" },
    { key: "notams", label: "NOTAMs / TFRs", icon: "fa-solid fa-ban", color: "#ef5350", target: "qlNotams" },
    { key: "militaryFlights", label: "Military Flights", icon: "fa-solid fa-jet-fighter", color: "#ef5350", target: "qlMilitaryFlights" },
    { key: "airbases", label: "Airbases", icon: "fa-solid fa-tower-observation", color: "#ff7043", target: "qlAirbases" },
    { key: "militaryBases", label: "Military Bases", icon: "fa-solid fa-shield-halved", color: "#ff5252", target: "qlMilitaryBases" },
    { key: "navalVessels", label: "Naval Vessels", icon: "fa-solid fa-ship", color: "#42a5f5", target: "qlNavalVessels" },
    { key: "strikes", label: "Strikes", icon: "fa-solid fa-crosshairs", color: "#e040fb", target: "qlStrikes" },
    { key: "cables", label: "Submarine Cables", icon: "fa-solid fa-network-wired", color: "#00bcd4", target: "qlCables" },
    { key: "pipelines", label: "Pipelines", icon: "fa-solid fa-oil-well", color: "#ff6d00", target: "qlPipelines" },
    { key: "railways", label: "Railways", icon: "fa-solid fa-train", color: "#90a4ae", target: "qlRailways" },
    { key: "powerPlants", label: "Power Plants", icon: "fa-solid fa-plug", color: "#ffc107", target: "qlPowerPlants" },
    { key: "cameras", label: "Webcams", icon: "fa-solid fa-video", color: "#29b6f6", target: "qlCameras" },
    { key: "financial", label: "Markets", icon: "fa-solid fa-chart-line", color: "#66bb6a", target: "qlFinancial" },
    { key: "cities", label: "Cities", icon: "fa-solid fa-city", color: "#ffd54f", target: "qlCities" },
    { key: "airports", label: "Airports", icon: "fa-solid fa-tower-broadcast", color: "#81c784", target: "qlAirports" },
    { key: "borders", label: "Borders", icon: "fa-solid fa-map", color: "#4fc3f7", target: "qlBorders" },
    { key: "terrain", label: "3D Terrain", icon: "fa-solid fa-mountain", color: "#a1887f", target: "qlTerrain" },
  ].freeze

  def meta_title
    meta_tags[:title]
  end

  def meta_description
    meta_tags[:description]
  end

  def meta_image_url
    absolute_public_url(meta_tags[:image_path])
  end

  def meta_url
    request.original_url
  end

  def meta_tags
    @meta_tags ||= begin
      defaults = {
        title: "GlobeTracker | Live Global Tracking",
        description: "Live global tracking for conflict events, conflict theaters, infrastructure, flights, ships, news, and cross-layer insights.",
        image_path: "/og-card.png",
        image_alt: "GlobeTracker live intelligence globe",
        type: "website",
        site_name: "GlobeTracker",
      }

      page_specific = case [controller_name, action_name]
      when [ "pages", "landing" ]
        {
          title: "GlobeTracker | Geospatial Intelligence Workspace",
          description: "A live geospatial intelligence workspace for aviation, maritime, infrastructure, conflict, and cross-layer analysis.",
        }
      when [ "pages", "sources" ]
        {
          title: "Sources | GlobeTracker",
          description: "Inspect the live source inventory and data coverage powering GlobeTracker.",
        }
      when [ "pages", "about" ]
        {
          title: "About | GlobeTracker",
          description: "Learn how GlobeTracker fuses live events, infrastructure, tracking, and intelligence signals into one operational globe.",
        }
      when [ "objects", "show" ]
        {
          title: [ @meta_title.presence, "GlobeTracker" ].compact.join(" | "),
          description: @meta_description.presence || "Inspect linked evidence, relationships, and geographic context for this GlobeTracker object.",
        }
      else
        {}
      end

      overrides = {
        title: @meta_title.presence,
        description: @meta_description.presence,
        image_path: @meta_image_path.presence,
        image_alt: @meta_image_alt.presence,
        type: @meta_type.presence,
      }.compact

      defaults.merge(page_specific).merge(overrides)
    end
  end

  def globe_toggle(target: nil, action:, label:, indent: false, dot: nil, muted: false, disabled: false, category: nil, checked: false)
    css = "sb-toggle"
    css += " sb-indent" if indent
    css += " sb-muted" if muted

    input_data = { action: "change->globe##{action}" }
    input_data[:globe_target] = target if target
    input_data[:category] = category if category

    content_tag(:label, class: css) do
      concat tag.input(type: "checkbox", data: input_data, disabled: disabled, checked: checked || nil)
      concat tag.span(class: "sb-toggle-track")
      if dot
        concat content_tag(:span, class: "sb-with-dot") {
          concat tag.span(class: "sb-dot", style: "--dot: #{dot};")
          concat label
        }
      else
        concat tag.span(label)
      end
    end
  end

  def globe_map_href
    return area_workspace_globe_href(@area_workspace) if defined?(@area_workspace) && @area_workspace.present? && respond_to?(:area_workspace_globe_href)

    root_path
  end

  def sidebar_primary_layers
    PRIMARY_SIDEBAR_LAYER_DEFS
  end

  def sidebar_advanced_library_layers
    ADVANCED_SIDEBAR_LIBRARY_DEFS
  end

  def enabled_sidebar_library_layers(user = current_user)
    prefs = user&.preferences || {}
    layer_prefs = prefs["layers"].is_a?(Hash) ? prefs["layers"] : {}
    enabled = Array(prefs["enabled_layers"]).map(&:to_s)

    layer_prefs.each do |key, value|
      enabled << key.to_s if value == true
    end

    sat_categories = layer_prefs["satCategories"]
    enabled << "satellites" if sat_categories.is_a?(Hash) && sat_categories.values.any?

    allowed = sidebar_advanced_library_layers.map { |layer| layer[:key] }
    enabled.uniq.select { |key| allowed.include?(key) }
  end

  def javascript_importmap_tags_for_revision(entry_point = "application", importmap: Rails.application.importmap)
    cache_key = Rails.env.production? ? entry_point.to_s : "#{entry_point}:#{app_revision}"
    importmap_json = importmap.to_json(resolver: self, cache_key: "#{cache_key}:json")
    preload_packages = importmap.preloaded_module_packages(resolver: self, entry_point:, cache_key: "#{cache_key}:preload")
    nonce = request&.content_security_policy_nonce

    safe_join [
      javascript_inline_importmap_tag(importmap_json),
      safe_join(preload_packages.map { |path, package|
        tag.link rel: "modulepreload", href: path, nonce:, integrity: package.integrity
      }, "\n"),
      javascript_import_module_tag(entry_point),
    ], "\n"
  end

  def sidebar_advanced_library_layers_by_key
    @sidebar_advanced_library_layers_by_key ||= sidebar_advanced_library_layers.index_by { |layer| layer[:key] }
  end

  private

  def absolute_public_url(path)
    return path if path.to_s.start_with?("http://", "https://")

    host = request&.base_url.presence ||
      begin
        configured = ENV["APP_HOST"].presence
        configured.present? ? (configured.start_with?("http://", "https://") ? configured : "https://#{configured}") : nil
      end ||
      "https://globe.haumer.ai"

    "#{host}#{path}"
  end
end
