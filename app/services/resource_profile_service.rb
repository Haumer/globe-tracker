class ResourceProfileService
  RESOURCE_LABELS = {
    "oil" => "Oil",
    "gas" => "Gas",
    "products" => "Refined products",
    "lng" => "LNG",
    "container" => "Container trade",
    "grain" => "Grain",
    "trade" => "Trade",
    "semiconductors" => "Semiconductors",
  }.freeze

  def self.call(primary_object:)
    new(primary_object: primary_object).call
  end

  def self.for(kind:, identifier:, title: nil, object_type: nil)
    primary_object = Struct.new(:object_kind, :object_identifier, :title, :object_type).new(
      kind,
      identifier,
      title,
      object_type
    )
    new(primary_object: primary_object).call
  end

  def initialize(primary_object:)
    @primary_object = primary_object
  end

  def call
    return nil unless @primary_object.present?

    case @primary_object.object_kind.to_s
    when "chokepoint"
      build_chokepoint_profile
    when "pipeline"
      build_pipeline_profile
    when "power_plant"
      build_power_plant_profile
    else
      nil
    end
  end

  private

  def build_chokepoint_profile
    chokepoint = resolve_chokepoint
    return nil unless chokepoint.present?

    flows = chokepoint[:flows].to_h
    top_flows = flows.first(3).map do |key, data|
      label = RESOURCE_LABELS.fetch(key.to_s, key.to_s.tr("_", " ").titleize)
      pct = data[:pct].presence
      pct.present? ? "#{label} #{pct}% global flow" : data[:note]
    end.compact

    {
      title: "Resource Context",
      subtitle: "Strategic flow node",
      summary: chokepoint[:description].presence || "Concentrates global trade and resource flows through a narrow corridor.",
      metrics: [
        { label: "Primary flows", value: top_flows.first || "Strategic maritime traffic" },
        { label: "Countries", value: Array(chokepoint[:countries]).any? ? Array(chokepoint[:countries]).join(", ") : "Unknown" },
        { label: "Risk factors", value: Array(chokepoint[:risk_factors]).any? ? Array(chokepoint[:risk_factors]).first(2).join(" · ") : "None" },
      ],
    }
  end

  def build_pipeline_profile
    pipeline = Pipeline.find_by(pipeline_id: @primary_object.object_identifier) || Pipeline.find_by(name: @primary_object.title)
    type = (pipeline&.pipeline_type || @primary_object.object_type).to_s
    resource_label = pipeline_resource_label(type)
    status = pipeline&.status.to_s.tr("_", " ").presence
    length = pipeline&.length_km
    country = pipeline&.country.presence

    {
      title: "Resource Context",
      subtitle: "Resource carrier",
      summary: [resource_label.present? ? "Carries #{resource_label.downcase}" : nil, country.present? ? "through #{country}" : nil].compact.join(" "),
      metrics: [
        { label: "Resource", value: resource_label.presence || "Pipeline" },
        { label: "Status", value: status&.titleize || "Unknown" },
        { label: "Length", value: length.present? ? "#{length.to_f.round.to_i.to_fs(:delimited)} km" : "Unknown" },
        { label: "Country", value: country || "Multi-country / unknown" },
      ],
    }
  end

  def build_power_plant_profile
    plant = resolve_power_plant
    fuel = plant&.primary_fuel.presence || @primary_object.object_type.presence || "Unknown fuel"
    capacity = plant&.capacity_mw
    country = plant&.country_code.presence || plant&.country_name.presence
    commissioned = plant&.commissioning_year

    {
      title: "Resource Context",
      subtitle: "Resource transformation",
      summary: "Consumes #{fuel.to_s.downcase} to produce electricity.",
      metrics: [
        { label: "Input fuel", value: fuel.to_s.titleize },
        { label: "Output", value: "Electricity" },
        { label: "Capacity", value: capacity.present? ? "#{capacity.to_f.round.to_i.to_fs(:delimited)} MW" : "Unknown" },
        { label: "Country", value: country || "Unknown" },
        { label: "Commissioned", value: commissioned.present? ? commissioned : "Unknown" },
      ],
    }
  end

  def resolve_power_plant
    identifier = @primary_object.object_identifier
    if identifier.to_s.match?(/\A\d+\z/)
      PowerPlant.find_by(id: identifier)
    else
      PowerPlant.find_by(gppd_idnr: identifier) || PowerPlant.find_by(name: @primary_object.title)
    end
  end

  def resolve_chokepoint
    identifier = @primary_object.object_identifier.to_s
    if ChokepointMonitorService::CHOKEPOINTS.key?(identifier.to_sym)
      ChokepointMonitorService::CHOKEPOINTS.fetch(identifier.to_sym)
    else
      ChokepointMonitorService::CHOKEPOINTS.values.find { |entry| entry[:name] == @primary_object.title }
    end
  end

  def pipeline_resource_label(value)
    RESOURCE_LABELS.fetch(value.to_s.downcase, value.to_s.titleize.presence || "Pipeline")
  end
end
