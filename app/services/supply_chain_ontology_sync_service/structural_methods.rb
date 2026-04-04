class SupplyChainOntologySyncService
  module StructuralMethods
    private

    def sync_commodity_entities
      commodity_pairs.each do |commodity_key, commodity_name|
        entity = OntologySyncSupport.upsert_entity(
          canonical_key: commodity_entity_key(commodity_key),
          entity_type: "commodity",
          canonical_name: commodity_name,
          metadata: {
            "description" => "#{commodity_name} is tracked as a strategic supply-chain commodity.",
            "commodity_key" => commodity_key,
            "strategic" => true,
          }
        )

        OntologySyncSupport.upsert_alias(entity, commodity_name, alias_type: "official")
        @commodity_entities[commodity_key] = entity
      end
    end

    def sync_chokepoint_entities
      ChokepointMonitorService::CHOKEPOINTS.each_key do |chokepoint_key|
        chokepoint_entity_for(chokepoint_key)
      end
    end

    def commodity_pairs
      @commodity_pairs ||= begin
        names = SupplyChainCatalog.strategic_commodity_pairs.to_h

        country_commodity_dependencies.each do |dependency|
          names[dependency.commodity_key] ||= dependency.commodity_name.presence || SupplyChainCatalog.commodity_name_for(dependency.commodity_key)
        end
        country_chokepoint_exposures.each do |exposure|
          names[exposure.commodity_key] ||= exposure.commodity_name.presence || SupplyChainCatalog.commodity_name_for(exposure.commodity_key)
        end
        sector_input_profiles.each do |profile|
          next unless profile.input_kind == "commodity" || SupplyChainCatalog.commodity_name_for(profile.input_key).present?

          names[profile.input_key] ||= profile.input_name.presence || SupplyChainCatalog.commodity_name_for(profile.input_key)
        end

        names.compact.sort_by { |commodity_key, commodity_name| [commodity_name, commodity_key] }
      end
    end

    def structural_flow_rows
      @structural_flow_rows ||= begin
        rows_by_pair = baseline_structural_flow_rows.index_by { |row| [row.fetch(:chokepoint_key), row.fetch(:commodity_key)] }

        country_chokepoint_exposures.group_by { |row| [row.chokepoint_key, row.commodity_key] }.each do |(chokepoint_key, commodity_key), exposures|
          strongest = exposures.max_by { |row| row.exposure_score.to_f }
          top_countries = exposures.sort_by { |row| -row.exposure_score.to_f }.first(3).map(&:country_name)
          rows_by_pair[[chokepoint_key, commodity_key]] = {
            chokepoint_key: chokepoint_key,
            commodity_key: commodity_key,
            confidence: confidence_from_score(strongest.exposure_score, floor: 0.45),
            explanation: "#{chokepoint_name_for(chokepoint_key)} is a structural route dependency for #{SupplyChainCatalog.commodity_name_for(commodity_key) || commodity_key.to_s.humanize}, with downstream import exposure in #{top_countries.join(', ')}.",
            metadata: {
              "chokepoint_key" => chokepoint_key,
              "commodity_key" => commodity_key,
              "country_count" => exposures.map(&:country_code_alpha3).uniq.size,
              "max_exposure_score" => strongest.exposure_score&.to_f,
              "source_kind" => exposures.all? { |row| row.metadata["estimated"] } ? "estimated_country_exposure" : "country_exposure",
            },
            evidence_rows: exposures.sort_by { |row| -row.exposure_score.to_f }.first(3),
          }
        end

        rows_by_pair.values.sort_by { |row| [row.fetch(:chokepoint_key), row.fetch(:commodity_key)] }
      end
    end

    def baseline_structural_flow_rows
      @baseline_structural_flow_rows ||= begin
        rows = []

        ChokepointMonitorService::CHOKEPOINTS.each do |chokepoint_key, config|
          flows = config[:flows] || {}

          SupplyChainCatalog.strategic_commodity_pairs.each do |commodity_key, commodity_name|
            flow_type = SupplyChainCatalog.commodity_flow_type_for(commodity_key)
            next if flow_type.blank?

            flow = flows[flow_type]
            next if flow.blank?

            rows << {
              chokepoint_key: chokepoint_key.to_s,
              commodity_key: commodity_key,
              confidence: baseline_flow_confidence(flow[:pct]),
              explanation: "#{config.fetch(:name)} is a structural route dependency for #{commodity_name}. #{flow[:note]}",
              metadata: {
                "chokepoint_key" => chokepoint_key.to_s,
                "commodity_key" => commodity_key,
                "flow_type" => flow_type.to_s,
                "flow_share_pct" => flow[:pct],
                "flow_volume" => flow[:volume],
                "source_kind" => "global_chokepoint_flow",
              }.compact,
            }
          end
        end

        SupplyChainCatalog::CHOKEPOINT_ROUTE_PRIORS.each do |prior|
          Array(prior[:commodity_keys]).each do |commodity_key|
            next if rows.any? { |row| row[:chokepoint_key] == prior.fetch(:chokepoint_key).to_s && row[:commodity_key] == commodity_key }

            commodity_name = SupplyChainCatalog.commodity_name_for(commodity_key)
            next if commodity_name.blank?

            rows << {
              chokepoint_key: prior.fetch(:chokepoint_key).to_s,
              commodity_key: commodity_key,
              confidence: 0.5,
              explanation: "#{chokepoint_name_for(prior.fetch(:chokepoint_key))} is modeled as a route dependency for #{commodity_name}. #{prior.fetch(:note)}",
              metadata: {
                "chokepoint_key" => prior.fetch(:chokepoint_key).to_s,
                "commodity_key" => commodity_key,
                "destination_country_alpha3" => Array(prior[:destination_country_alpha3]),
                "requires_any_source_chokepoint" => Array(prior[:requires_any_source_chokepoint]).map(&:to_s),
                "source_kind" => "route_prior",
              },
            }
          end
        end

        rows
      end
    end

    def input_entity_for_profile(profile)
      if profile.input_kind == "commodity" || SupplyChainCatalog.commodity_name_for(profile.input_key).present?
        @commodity_entities[profile.input_key] ||= begin
          name = profile.input_name.presence || SupplyChainCatalog.commodity_name_for(profile.input_key) || profile.input_key.to_s.humanize
          OntologySyncSupport.upsert_entity(
            canonical_key: commodity_entity_key(profile.input_key),
            entity_type: "commodity",
            canonical_name: name,
            metadata: {
              "description" => "#{name} is tracked as a strategic supply-chain commodity.",
              "commodity_key" => profile.input_key,
              "strategic" => true,
            }
          )
        end
      else
        @input_entities[[profile.input_kind, profile.input_key]] ||= OntologySyncSupport.upsert_entity(
          canonical_key: "input:#{profile.input_kind}:#{OntologySyncSupport.slugify(profile.input_key)}",
          entity_type: INPUT_ENTITY_TYPE,
          canonical_name: display_name_for_input_profile(profile),
          metadata: {
            "description" => "#{display_name_for_input_profile(profile)} is a modeled production input.",
            "input_kind" => profile.input_kind,
            "input_key" => profile.input_key,
          }
        )
      end
    end

    def chokepoint_entity_for(chokepoint_key)
      @chokepoint_entities[chokepoint_key.to_s] ||= begin
        config = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key.to_sym)
        entity = OntologySyncSupport.upsert_entity(
          canonical_key: "corridor:chokepoint:#{chokepoint_key}",
          entity_type: "corridor",
          canonical_name: config.fetch(:name),
          metadata: {
            "strategic_kind" => "chokepoint",
            "description" => config[:description],
            "latitude" => config[:lat],
            "longitude" => config[:lng],
            "radius_km" => config[:radius_km],
            "countries" => config[:countries],
            "flows" => config[:flows],
          }.compact
        )
        OntologySyncSupport.upsert_alias(entity, config.fetch(:name), alias_type: "official")
        entity
      end
    end

    def baseline_flow_confidence(flow_share_pct)
      normalized = (flow_share_pct.to_f / 30.0).clamp(0.0, 1.0)
      confidence_from_score(normalized, floor: 0.42)
    end

    def chokepoint_name_for(chokepoint_key)
      ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key.to_sym).fetch(:name)
    end

    def display_name_for_input_profile(profile)
      profile.input_name.presence || profile.input_key.to_s.humanize
    end
  end
end
