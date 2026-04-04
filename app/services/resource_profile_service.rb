class ResourceProfileService
  RESOURCE_LABELS = {
    "oil" => "Oil",
    "gas" => "Gas",
    "products" => "Refined products",
  }.freeze

  def self.call(primary_object:)
    new(primary_object: primary_object).call
  end

  def initialize(primary_object:)
    @primary_object = primary_object
  end

  def call
    return nil unless @primary_object.present?

    case @primary_object.object_kind.to_s
    when "pipeline"
      build_pipeline_profile
    when "power_plant"
      build_power_plant_profile
    else
      nil
    end
  end

  private

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

  def pipeline_resource_label(value)
    RESOURCE_LABELS.fetch(value.to_s.downcase, value.to_s.titleize.presence || "Pipeline")
  end
end
