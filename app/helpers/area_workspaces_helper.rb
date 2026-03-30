module AreaWorkspacesHelper
  LAYER_SHORT = {
    "flights" => "fl",
    "trails" => "tr",
    "ships" => "sh",
    "borders" => "bd",
    "cities" => "ct",
    "airports" => "ap",
    "earthquakes" => "eq",
    "naturalEvents" => "ev",
    "cameras" => "cm",
    "gpsJamming" => "gj",
    "news" => "nw",
    "cables" => "cb",
    "outages" => "ou",
    "powerPlants" => "pp",
    "conflicts" => "cf",
    "traffic" => "tf",
    "notams" => "nt",
    "terrain" => "tn",
    "fireHotspots" => "fh",
    "weather" => "wx",
    "financial" => "fn",
    "insights" => "in",
    "situations" => "si",
    "trains" => "tns",
    "railways" => "rl",
    "pipelines" => "pl",
    "militaryBases" => "mb",
    "airbases" => "ab",
    "chokepoints" => "cp",
  }.freeze

  def area_workspace_globe_href(area_workspace)
    root_path + area_workspace_globe_anchor(area_workspace)
  end

  def area_workspace_globe_anchor(area_workspace)
    parts = []
    parts << area_workspace_camera_anchor(area_workspace)

    layer_codes = Array(area_workspace.default_layers).filter_map { |layer| LAYER_SHORT[layer.to_s] }
    parts << "l:#{layer_codes.join(',')}" if layer_codes.any?

    case area_workspace.scope_type
    when "preset_region"
      region_key = area_workspace.region_key
      parts << "r:#{region_key}" if region_key.present?
    when "country_set"
      countries = area_workspace.country_names
      parts << "co:#{countries.join('|')}" if countries.any?
    when "bbox"
      metadata = area_workspace.scope_metadata.with_indifferent_access
      center = metadata[:center].with_indifferent_access if metadata[:center].respond_to?(:with_indifferent_access)
      radius_km = metadata[:radius_km].to_f
      if center.present? && radius_km.positive?
        parts << format("ci:%.4f,%.4f,%d", center[:lat].to_f, center[:lng].to_f, (radius_km * 1000).round)
      end
    end

    "##{parts.compact.join(';')}"
  end

  private

  def area_workspace_camera_anchor(area_workspace)
    metadata = area_workspace.scope_metadata.with_indifferent_access
    camera = metadata[:camera].with_indifferent_access if metadata[:camera].respond_to?(:with_indifferent_access)

    lat = camera&.[](:lat).presence || area_bounds_center(area_workspace)[:lat]
    lng = camera&.[](:lng).presence || area_bounds_center(area_workspace)[:lng]
    height = camera&.[](:height).presence || area_workspace_camera_height(area_workspace)
    heading = camera&.[](:heading).presence || 0
    pitch = camera&.[](:pitch).presence || -1.12

    format("%.4f,%.4f,%d,%.3f,%.3f", lat.to_f, lng.to_f, height.to_i, heading.to_f, pitch.to_f)
  end

  def area_bounds_center(area_workspace)
    bounds = area_workspace.bounds_hash
    {
      lat: ((bounds[:lamin].to_f + bounds[:lamax].to_f) / 2.0),
      lng: ((bounds[:lomin].to_f + bounds[:lomax].to_f) / 2.0),
    }
  end

  def area_workspace_camera_height(area_workspace)
    metadata = area_workspace.scope_metadata.with_indifferent_access
    radius_km = metadata[:radius_km].to_f
    return [(radius_km * 2200).round, 300_000].max if radius_km.positive?

    bounds = area_workspace.bounds_hash
    center = area_bounds_center(area_workspace)
    lat_span_km = (bounds[:lamax].to_f - bounds[:lamin].to_f).abs * 111.0
    lng_span_km = (bounds[:lomax].to_f - bounds[:lomin].to_f).abs * 111.0 * Math.cos(center[:lat].to_f * Math::PI / 180).abs
    [[lat_span_km, lng_span_km].max.round * 1000, 300_000].max.clamp(300_000, 12_000_000)
  end
end
