module ObjectsHelper
  def object_view_request_for_node(node)
    return unless node.present?

    node_type = node[:node_type] || node["node_type"]
    canonical_key = node[:canonical_key] || node["canonical_key"]
    entity_type = node[:entity_type] || node["entity_type"]
    name = node[:name] || node["name"]

    if node_type == "entity"
      return { kind: "theater", id: canonical_key || name } if entity_type == "theater"
      return { kind: "commodity", id: canonical_key || name } if entity_type == "commodity"
      if entity_type == "corridor" && canonical_key.to_s.start_with?("corridor:chokepoint:")
        return { kind: "chokepoint", id: canonical_key.to_s.split(":").last }
      end
      return { kind: "entity", id: canonical_key } if canonical_key.present?
    end

    if node_type == "event" && canonical_key.to_s.start_with?("news-story-cluster:")
      return { kind: "news_story_cluster", id: canonical_key.to_s.delete_prefix("news-story-cluster:") }
    end

    nil
  end

  def object_view_request_for_evidence(evidence)
    return unless evidence.present?

    type = evidence[:type] || evidence["type"]
    if type == "news_story_cluster"
      cluster_key = evidence[:cluster_key] || evidence["cluster_key"]
      return { kind: "news_story_cluster", id: cluster_key } if cluster_key.present?
    end

    if type == "commodity_price"
      symbol = evidence[:symbol] || evidence["symbol"]
      return { kind: "commodity", id: symbol } if symbol.present?
    end

    nil
  end

  def object_view_href_for(request)
    return unless request.present?

    object_view_path(kind: request.fetch(:kind), id: request.fetch(:id))
  end

  def object_globe_href_for(request, context)
    return root_path unless request.present?

    options = {
      focus_kind: request.fetch(:kind),
      focus_id: request.fetch(:id),
      focus_title: context.dig(:node, :name),
    }
    anchor = globe_focus_anchor_for(context)
    options[:anchor] = anchor if anchor.present?
    root_path(options)
  end

  def object_relation_label(value)
    value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def object_role_label(value)
    value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def object_confidence_label(value)
    return "—" if value.blank?

    number_to_percentage(value.to_f * 100, precision: value.to_f >= 0.95 ? 0 : 1)
  end

  def default_case_title_for(context)
    node_name = context.dig(:node, :name).presence || "Untitled Object"
    "#{node_name} case"
  end

  def case_source_payload_for(request, context)
    node = context[:node] || {}
    {
      object_kind: request.fetch(:kind),
      object_identifier: request.fetch(:id),
      title: node[:name],
      summary: node[:summary],
      object_type: node[:entity_type] || node[:event_type] || node[:node_type],
      latitude: node[:latitude],
      longitude: node[:longitude],
      source_context: {
        canonical_key: node[:canonical_key],
        node_type: node[:node_type],
        verification_status: node[:verification_status],
        relationship_count: Array(context[:relationships]).size,
        evidence_count: Array(context[:evidence]).size,
        membership_count: Array(context[:memberships]).size,
        globe_anchor: globe_focus_anchor_for(context),
      }.compact,
    }.compact
  end

  private

  def globe_focus_anchor_for(context)
    node = context[:node] || {}
    lat = node[:latitude]
    lng = node[:longitude]
    return if lat.blank? || lng.blank?

    "#{lat.to_f.round(4)},#{lng.to_f.round(4)},2500000,0,-1.25"
  end
end
