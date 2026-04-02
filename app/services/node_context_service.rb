class NodeContextService
  class UnsupportedNodeError < StandardError; end
  class NodeNotFoundError < StandardError; end

  class << self
    def resolve(kind:, id:)
      case kind.to_s
      when "news_story_cluster"
        serialize_event_context(resolve_story_cluster_event(id))
      when "chokepoint"
        serialize_entity_context(resolve_chokepoint_entity(id))
      when "theater"
        serialize_entity_context(resolve_theater_entity(id))
      when "commodity"
        serialize_entity_context(resolve_commodity_entity(id))
      when "entity"
        serialize_entity_context(resolve_generic_entity(id))
      else
        raise UnsupportedNodeError, "unsupported node context kind: #{kind}"
      end
    end

    private

    def resolve_story_cluster_event(identifier)
      event = OntologyEvent.includes(:place_entity, :primary_story_cluster, ontology_event_entities: :ontology_entity, ontology_evidence_links: :evidence)
        .find_by(canonical_key: "news-story-cluster:#{identifier}")
      event ||= OntologyEvent.includes(:place_entity, :primary_story_cluster, ontology_event_entities: :ontology_entity, ontology_evidence_links: :evidence)
        .joins(:primary_story_cluster)
        .find_by(news_story_clusters: { cluster_key: identifier })
      event || raise(NodeNotFoundError, "news story cluster context not found")
    end

    def resolve_chokepoint_entity(identifier)
      key = resolve_chokepoint_key(identifier)
      entity = OntologyEntity.find_by(canonical_key: "corridor:chokepoint:#{key}") if key.present?
      entity ||= OntologyEntity.find_by(entity_type: "corridor", canonical_name: identifier.to_s)
      entity || raise(NodeNotFoundError, "chokepoint context not found")
    end

    def resolve_theater_entity(identifier)
      raw = identifier.to_s.strip
      entity = OntologyEntity.find_by(canonical_key: "theater:#{OntologySyncSupport.slugify(raw)}") if raw.present?
      entity ||= OntologyEntity.where(entity_type: "theater").find_by("LOWER(canonical_name) = ?", raw.downcase)
      entity ||= OntologyEntity.joins(:ontology_entity_aliases)
        .where(entity_type: "theater")
        .find_by("LOWER(ontology_entity_aliases.name) = ?", raw.downcase)
      entity || raise(NodeNotFoundError, "theater context not found")
    end

    def resolve_commodity_entity(identifier)
      raw = identifier.to_s.strip
      entity = OntologyEntity.find_by(canonical_key: raw) if raw.start_with?("commodity:")
      entity ||= OntologyEntity.find_by(canonical_key: "commodity:#{raw.downcase}") if raw.present?
      entity ||= OntologyEntity.where(entity_type: "commodity").find_by("LOWER(canonical_name) = ?", raw.downcase)
      entity ||= OntologyEntity.joins(:ontology_entity_aliases)
        .where(entity_type: "commodity")
        .find_by("LOWER(ontology_entity_aliases.name) = ?", raw.downcase)
      entity || raise(NodeNotFoundError, "commodity context not found")
    end

    def resolve_generic_entity(identifier)
      raw = identifier.to_s.strip
      entity = OntologyEntity.find_by(canonical_key: raw) if raw.present?
      entity ||= OntologyEntity.where("LOWER(canonical_name) = ?", raw.downcase).first if raw.present?
      entity ||= OntologyEntity.joins(:ontology_entity_aliases)
        .find_by("LOWER(ontology_entity_aliases.name) = ?", raw.downcase) if raw.present?
      entity || raise(NodeNotFoundError, "entity context not found")
    end

    def resolve_chokepoint_key(identifier)
      raw = identifier.to_s
      return if raw.blank?

      return raw if ChokepointMonitorService::CHOKEPOINTS.key?(raw.to_sym)

      match = ChokepointMonitorService::CHOKEPOINTS.find do |key, config|
        [
          key.to_s,
          key.to_s.tr("_", " "),
          config.fetch(:name),
          OntologySyncSupport.slugify(config.fetch(:name)),
        ].any? { |candidate| candidate.to_s.casecmp?(raw) }
      end

      match&.first&.to_s
    end

    def serialize_entity_context(entity)
      {
        node: serialize_node(entity),
        memberships: [],
        evidence: serialize_entity_evidence(entity),
        relationships: serialize_relationships(entity),
      }
    end

    def serialize_event_context(event)
      {
        node: serialize_node(event),
        memberships: event.ontology_event_entities.includes(:ontology_entity).map do |membership|
          {
            role: membership.role,
            confidence: membership.confidence.to_f.round(2),
            node: serialize_node(membership.ontology_entity),
          }
        end,
        evidence: event.ontology_evidence_links.includes(:evidence).map do |link|
          serialize_evidence_link(link)
        end,
        relationships: serialize_relationships(event),
      }
    end

    def serialize_relationships(node)
      outgoing = node.outgoing_ontology_relationships.active.includes(:ontology_relationship_evidences).to_a.map do |relationship|
        serialize_relationship(relationship, direction: "outgoing")
      end
      incoming = node.incoming_ontology_relationships.active.includes(:ontology_relationship_evidences).to_a.map do |relationship|
        serialize_relationship(relationship, direction: "incoming")
      end

      (outgoing + incoming)
        .sort_by { |relationship| [-relationship.fetch(:confidence), relationship.fetch(:node).fetch(:name).to_s] }
        .first(8)
    end

    def serialize_entity_evidence(entity)
      relationships = node_relationship_records(entity)

      relationships.flat_map do |relationship|
        relationship.ontology_relationship_evidences.includes(:evidence).map do |evidence_link|
          serialize_relationship_evidence(evidence_link)
        end
      end
        .uniq { |evidence| [evidence[:type], evidence[:id], evidence[:role]] }
        .sort_by { |evidence| [-evidence.fetch(:confidence, 0), evidence.fetch(:label).to_s] }
        .first(6)
    end

    def node_relationship_records(node)
      node.outgoing_ontology_relationships.active.includes(ontology_relationship_evidences: :evidence).to_a +
        node.incoming_ontology_relationships.active.includes(ontology_relationship_evidences: :evidence).to_a
    end

    def serialize_relationship(relationship, direction:)
      counterparty = direction == "outgoing" ? relationship.target_node : relationship.source_node

      {
        direction: direction,
        relation_type: relationship.relation_type,
        confidence: relationship.confidence.to_f.round(2),
        explanation: relationship.explanation,
        node: serialize_node(counterparty),
        evidence: relationship.ontology_relationship_evidences.includes(:evidence).map do |evidence_link|
          serialize_relationship_evidence(evidence_link)
        end.first(4),
      }
    end

    def serialize_node(node)
      case node
      when OntologyEntity
        {
          node_type: "entity",
          id: node.id,
          canonical_key: node.canonical_key,
          entity_type: node.entity_type,
          name: display_name_for_entity(node),
          summary: entity_summary(node),
        }.merge(node_coordinates(node)).compact
      when OntologyEvent
        {
          node_type: "event",
          id: node.id,
          canonical_key: node.canonical_key,
          event_family: node.event_family,
          event_type: node.event_type,
          name: node.metadata["canonical_title"] || node.primary_story_cluster&.canonical_title || node.canonical_key,
          summary: node.metadata["location_name"],
          verification_status: node.verification_status,
        }.merge(node_coordinates(node)).compact
      else
        {
          node_type: node.class.name,
          id: node.id,
          name: node.try(:canonical_name) || node.try(:canonical_title) || node.try(:name) || node.class.name,
        }
      end
    end

    def entity_summary(entity)
      return entity.metadata["description"] if entity.metadata["description"].present?
      return entity.metadata["location_name"] if entity.metadata["location_name"].present?

      case entity.entity_type
      when "theater"
        parts = []
        cluster_count = entity.metadata["cluster_count"].to_i
        total_sources = entity.metadata["total_sources"].to_i
        situation_names = Array(entity.metadata["situation_names"]).first(2)

        parts << pluralize(cluster_count, "cluster") if cluster_count.positive?
        parts << pluralize(total_sources, "source") if total_sources.positive?
        parts << situation_names.join(", ") if situation_names.any?
        parts.join(" · ").presence
      when "commodity"
        parts = []
        parts << entity.metadata["symbol"] if entity.metadata["symbol"].present?
        parts << format_price(entity.metadata["latest_price"], entity.metadata["unit"]) if entity.metadata["latest_price"].present?
        parts << format_change(entity.metadata["change_pct"]) if entity.metadata["change_pct"].present?
        parts << entity.metadata["region"] if entity.metadata["region"].present?
        parts.join(" · ").presence
      when "country"
        parts = []
        parts << format_usd_short(entity.metadata["gdp_nominal_usd"], prefix: "GDP ") if entity.metadata["gdp_nominal_usd"].present?
        parts << "#{entity.metadata["imports_goods_services_pct_gdp"].to_f.round(1)}% imports/GDP" if entity.metadata["imports_goods_services_pct_gdp"].present?
        parts << "#{entity.metadata["energy_imports_net_pct_energy_use"].to_f.round(1)}% net energy imports" if entity.metadata["energy_imports_net_pct_energy_use"].present?
        parts << entity.metadata["latest_year"] if entity.metadata["latest_year"].present?
        parts.join(" · ").presence
      when "sector"
        parts = []
        parts << entity.metadata["country_name"] if entity.metadata["country_name"].present?
        parts << "#{entity.metadata["share_pct"].to_f.round(1)}% GDP share" if entity.metadata["share_pct"].present?
        parts << "rank #{entity.metadata["rank"]}" if entity.metadata["rank"].present?
        parts.join(" · ").presence
      when "input"
        parts = []
        parts << entity.metadata["input_kind"] if entity.metadata["input_kind"].present?
        parts << entity.metadata["input_key"] if entity.metadata["input_key"].present?
        parts.join(" · ").presence
      when "airport"
        parts = []
        parts << entity.metadata["airport_type"] if entity.metadata["airport_type"].present?
        parts << entity.country_code if entity.country_code.present?
        parts << entity.metadata["municipality"] if entity.metadata["municipality"].present?
        parts.join(" · ").presence
      when "military_base"
        parts = []
        parts << entity.metadata["base_type"] if entity.metadata["base_type"].present?
        parts << entity.metadata["operator"] if entity.metadata["operator"].present?
        parts << entity.metadata["country"] if entity.metadata["country"].present?
        parts.join(" · ").presence
      when "power_plant"
        parts = []
        parts << entity.metadata["primary_fuel"] if entity.metadata["primary_fuel"].present?
        parts << "#{entity.metadata["capacity_mw"].to_f.round} MW" if entity.metadata["capacity_mw"].present?
        parts << entity.country_code if entity.country_code.present?
        parts.join(" · ").presence
      when "submarine_cable"
        parts = []
        parts << pluralize(entity.metadata["landing_point_count"].to_i, "landing point") if entity.metadata["landing_point_count"].present?
        parts << entity.metadata["country_codes"]&.first(3)&.join(", ") if entity.metadata["country_codes"].is_a?(Array) && entity.metadata["country_codes"].any?
        parts.join(" · ").presence
      when "asset"
        case entity.metadata["asset_kind"]
        when "flight"
          parts = []
          parts << "flight"
          parts << "military" if entity.metadata["military"]
          parts << entity.metadata["origin_country"] if entity.metadata["origin_country"].present?
          parts << entity.metadata["aircraft_type"] if entity.metadata["aircraft_type"].present?
          parts.join(" · ").presence
        when "ship"
          parts = []
          parts << "ship"
          parts << entity.metadata["flag"] if entity.metadata["flag"].present?
          parts << entity.metadata["destination"] if entity.metadata["destination"].present?
          parts.join(" · ").presence
        when "camera"
          parts = []
          parts << "camera"
          parts << entity.metadata["source"] if entity.metadata["source"].present?
          parts << entity.metadata["city"] if entity.metadata["city"].present?
          parts << entity.metadata["country"] if entity.metadata["country"].present?
          parts << "live" if entity.metadata["is_live"]
          parts.join(" · ").presence
        end
      else
        nil
      end
    end

    def display_name_for_entity(entity)
      if entity.entity_type == "corridor" && entity.canonical_key.to_s.start_with?("corridor:chokepoint:")
        chokepoint_key = entity.canonical_key.to_s.split(":").last
        config = ChokepointMonitorService::CHOKEPOINTS[chokepoint_key.to_sym]
        return config[:name] if config.present?
      end

      entity.canonical_name
    end

    def node_coordinates(node)
      case node
      when OntologyEntity
        latitude = node.metadata["latitude"]
        longitude = node.metadata["longitude"]
      when OntologyEvent
        latitude = node.place_entity&.metadata&.[]("latitude") || node.primary_story_cluster&.latitude
        longitude = node.place_entity&.metadata&.[]("longitude") || node.primary_story_cluster&.longitude
      else
        return {}
      end

      return {} if latitude.blank? || longitude.blank?

      {
        latitude: latitude.to_f,
        longitude: longitude.to_f,
      }
    end

    def serialize_evidence_link(link)
      payload = serialize_evidence(link.evidence)
      payload.merge(
        role: link.evidence_role,
        confidence: link.confidence.to_f.round(2)
      )
    end

    def serialize_relationship_evidence(link)
      payload = serialize_evidence(link.evidence)
      payload.merge(
        role: link.evidence_role,
        confidence: link.confidence.to_f.round(2)
      )
    end

    def serialize_evidence(evidence)
      case evidence
      when NewsStoryCluster
        {
          type: "news_story_cluster",
          id: evidence.id,
          cluster_key: evidence.cluster_key,
          label: evidence.canonical_title,
          meta: [pluralize(evidence.source_count, "source"), pluralize(evidence.article_count, "article")].compact.join(" · "),
        }
      when NewsArticle
        {
          type: "news_article",
          id: evidence.id,
          label: evidence.title.presence || evidence.url,
          meta: evidence.publisher_name || evidence.origin_source_name,
          url: evidence.url,
        }
      when CommodityPrice
        change = evidence.change_pct.present? ? "#{evidence.change_pct.to_f.positive? ? "+" : ""}#{evidence.change_pct}%" : nil
        {
          type: "commodity_price",
          id: evidence.id,
          symbol: evidence.symbol,
          label: evidence.name,
          meta: [evidence.symbol, change].compact.join(" · "),
        }
      when Flight
        {
          type: "flight",
          id: evidence.id,
          label: evidence.callsign.presence || evidence.icao24.presence || "Tracked flight",
          meta: [
            evidence.military? ? "military" : "civilian",
            evidence.origin_country,
            evidence.aircraft_type,
          ].compact.join(" · "),
        }
      when Ship
        {
          type: "ship",
          id: evidence.id,
          label: evidence.name.presence || evidence.mmsi.presence || "Tracked ship",
          meta: [
            evidence.flag,
            evidence.destination,
            (evidence.speed.present? ? "#{evidence.speed.to_f.round(1)}kt" : nil),
          ].compact.join(" · "),
        }
      when GpsJammingSnapshot
        {
          type: "gps_jamming_snapshot",
          id: evidence.id,
          label: "GPS jamming #{evidence.percentage.to_f.round(1)}%",
          meta: [evidence.level, evidence.recorded_at&.iso8601].compact.join(" · "),
        }
      when Notam
        {
          type: "notam",
          id: evidence.id,
          label: evidence.reason.presence || "Operational NOTAM",
          meta: [evidence.country, evidence.effective_start&.iso8601].compact.join(" · "),
        }
      when CountryProfile
        {
          type: "country_profile",
          id: evidence.id,
          label: evidence.country_name,
          meta: [
            format_usd_short(evidence.gdp_nominal_usd, prefix: "GDP "),
            (evidence.latest_year if evidence.latest_year.present?),
          ].compact.join(" · "),
        }
      when CountrySectorProfile
        {
          type: "country_sector_profile",
          id: evidence.id,
          label: "#{evidence.country_name} #{evidence.sector_name}",
          meta: [
            "#{evidence.share_pct.to_f.round(1)}% GDP share",
            ("rank #{evidence.rank}" if evidence.rank.present?),
          ].compact.join(" · "),
        }
      when SectorInputProfile
        {
          type: "sector_input_profile",
          id: evidence.id,
          label: evidence.input_name.presence || evidence.input_key.to_s.humanize,
          meta: [
            ("estimated" if evidence.metadata["estimated"]),
            evidence.input_kind,
            ("coeff #{evidence.coefficient.to_f.round(3)}" if evidence.coefficient.present?),
            evidence.scope_key,
          ].compact.join(" · "),
        }
      when CountryCommodityDependency
        {
          type: "country_commodity_dependency",
          id: evidence.id,
          label: "#{evidence.country_name} #{evidence.commodity_name.to_s.downcase} imports",
          meta: [
            ("estimated" if evidence.metadata["estimated"]),
            ("#{evidence.import_share_gdp_pct.to_f.round(2)}% GDP" if evidence.import_share_gdp_pct.present?),
            ("#{evidence.top_partner_country_name} #{evidence.top_partner_share_pct.to_f.round(1)}%" if evidence.top_partner_country_name.present? && evidence.top_partner_share_pct.present?),
          ].compact.join(" · "),
        }
      when CountryChokepointExposure
        {
          type: "country_chokepoint_exposure",
          id: evidence.id,
          label: "#{evidence.country_name} #{evidence.chokepoint_name} exposure",
          meta: [
            ("estimated" if evidence.metadata["estimated"]),
            evidence.commodity_name,
            ("score #{evidence.exposure_score.to_f.round(2)}" if evidence.exposure_score.present?),
          ].compact.join(" · "),
        }
      else
        {
          type: evidence.class.name.underscore,
          id: evidence.id,
          label: evidence.try(:canonical_name) || evidence.try(:canonical_title) || evidence.try(:title) || evidence.try(:name) || evidence.class.name,
        }
      end
    end

    def pluralize(count, noun)
      return if count.blank?

      "#{count} #{noun}#{count == 1 ? "" : "s"}"
    end

    def format_change(change_pct)
      value = change_pct.to_f
      "#{value.positive? ? "+" : ""}#{value.round(2)}%"
    end

    def format_price(price, unit)
      rendered = price.to_f.abs >= 100 ? price.to_f.round(1).to_s : price.to_f.round(2).to_s
      unit.present? ? "#{rendered} #{unit}" : rendered
    end

    def format_usd_short(value, prefix: "")
      return if value.blank?

      amount = value.to_f
      suffix = if amount >= 1_000_000_000_000
        "#{(amount / 1_000_000_000_000).round(2)}T"
      elsif amount >= 1_000_000_000
        "#{(amount / 1_000_000_000).round(1)}B"
      elsif amount >= 1_000_000
        "#{(amount / 1_000_000).round(1)}M"
      else
        amount.round.to_s
      end

      "#{prefix}$#{suffix}"
    end
  end
end
