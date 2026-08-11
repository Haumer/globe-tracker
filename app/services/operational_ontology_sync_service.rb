class OperationalOntologySyncService
  DEFAULT_BATCH_SIZE = 250
  BACKFILL_TARGETS = %w[flights ships outages].freeze
  ASSET_ENTITY_TYPE = "asset".freeze
  PLACE_ENTITY_TYPE = "place".freeze
  ORGANIZATION_ENTITY_TYPE = "organization".freeze
  RECENT_SYNC_CONFIG = {
    "flights" => { window: 15.minutes, throttle: 5.minutes },
    "ships" => { window: 20.minutes, throttle: 5.minutes },
    "outages" => { window: 2.hours, throttle: 5.minutes },
  }.freeze

  class << self
    def enqueue_backfill(batch_size: DEFAULT_BATCH_SIZE)
      BACKFILL_TARGETS.each do |target|
        OperationalOntologyBatchJob.perform_later(target, { "cursor" => 0, "batch_size" => batch_size })
      end
    end

    def enqueue_recent(target, batch_size: DEFAULT_BATCH_SIZE, now: Time.current)
      config = RECENT_SYNC_CONFIG.fetch(target.to_s) do
        raise ArgumentError, "unknown operational ontology sync target: #{target}"
      end

      throttle_seconds = config.fetch(:throttle).to_i
      slot = now.to_i / throttle_seconds
      cache_key = "ontology:operational:#{target}:recent:#{slot}"
      @recent_enqueue_slots ||= {}
      return false if @recent_enqueue_slots[target.to_s] == slot
      return false if Rails.cache.read(cache_key).present?

      @recent_enqueue_slots[target.to_s] = slot
      Rails.cache.write(cache_key, true, expires_in: throttle_seconds.seconds)

      OperationalOntologyBatchJob.perform_later(
        target.to_s,
        {
          "updated_after" => (now - config.fetch(:window)).iso8601,
          "batch_size" => batch_size,
        }
      )
      true
    end

    def sync_batch(target, ids: nil, cursor: nil, batch_size: DEFAULT_BATCH_SIZE, updated_after: nil)
      records = batch_relation(target, ids: ids, cursor: cursor, batch_size: batch_size, updated_after: updated_after).to_a
      records.each { |record| sync_record(target, record) }

      {
        records_fetched: records.size,
        records_stored: records.size,
        next_cursor: ids.present? || records.size < batch_size ? nil : records.last.id,
        batch_size: batch_size,
        updated_after: updated_after,
      }
    end

    def sync_all
      Flight.find_each { |flight| sync_flight(flight) }
      Ship.find_each { |ship| sync_ship(ship) }
      InternetOutage.find_each { |outage| sync_outage(outage) }
    end

    def sync_flight(flight)
      entity = OntologySyncSupport.upsert_entity(
        canonical_key: flight_entity_key(flight),
        entity_type: ASSET_ENTITY_TYPE,
        canonical_name: flight.callsign.presence || flight.icao24.presence || "Tracked flight",
        country_code: country_code_for_name(flight.origin_country),
        metadata: {
          "asset_kind" => "flight",
          "icao24" => flight.icao24,
          "callsign" => flight.callsign,
          "source" => flight.source,
          "origin_country" => flight.origin_country,
          "registration" => flight.registration,
          "aircraft_type" => flight.aircraft_type,
          "military" => flight.military,
          "category" => flight.category,
        }.compact
      )

      OntologySyncSupport.upsert_alias(entity, flight.callsign, alias_type: "callsign")
      OntologySyncSupport.upsert_alias(entity, flight.registration, alias_type: "registration")
      OntologySyncSupport.upsert_alias(entity, flight.icao24, alias_type: "icao24")
      OntologySyncSupport.upsert_link(entity, flight, role: "tracked_flight", method: "operational_ontology_sync_v1")
      supersede_sighting_links(entity, role: "tracked_flight", linkable_type: "Flight", current_id: flight.id)
      entity
    end

    def sync_ship(ship)
      entity = OntologySyncSupport.upsert_entity(
        canonical_key: ship_entity_key(ship),
        entity_type: ASSET_ENTITY_TYPE,
        canonical_name: ship.name.presence || ship.mmsi.presence || "Tracked ship",
        country_code: ship.flag.to_s.first(2).presence&.upcase,
        metadata: {
          "asset_kind" => "ship",
          "mmsi" => ship.mmsi,
          "ship_type" => ship.ship_type,
          "destination" => ship.destination,
          "flag" => ship.flag,
        }.compact
      )

      OntologySyncSupport.upsert_alias(entity, ship.name, alias_type: "official")
      OntologySyncSupport.upsert_alias(entity, ship.mmsi, alias_type: "mmsi")
      OntologySyncSupport.upsert_link(entity, ship, role: "tracked_ship", method: "operational_ontology_sync_v1")
      supersede_sighting_links(entity, role: "tracked_ship", linkable_type: "Ship", current_id: ship.id)
      entity
    end

    def sync_outage(outage)
      affected_entity = sync_outage_entity(outage)
      event = OntologySyncSupport.persist_upsert(OntologyEvent, canonical_key: outage_event_key(outage)) do |record|
        record.place_entity = affected_entity&.entity_type == PLACE_ENTITY_TYPE ? affected_entity : nil
        record.event_family = "infrastructure"
        record.event_type = "outage"
        record.status = outage.ended_at.present? ? "resolved" : "active"
        record.verification_status = "single_source"
        record.geo_precision = affected_entity&.entity_type == PLACE_ENTITY_TYPE ? "country" : "unknown"
        record.confidence = OntologySyncSupport.normalized_confidence(outage.score)
        record.source_reliability = 0.7
        record.geo_confidence = affected_entity&.entity_type == PLACE_ENTITY_TYPE ? 0.7 : 0.0
        record.started_at = outage.started_at
        record.ended_at = outage.ended_at
        record.first_seen_at ||= outage.started_at || outage.created_at
        record.last_seen_at = outage.ended_at || outage.updated_at
        record.metadata = {
          "datasource" => outage.datasource,
          "entity_type" => outage.entity_type,
          "entity_code" => outage.entity_code,
          "entity_name" => outage.entity_name,
          "level" => outage.level,
          "condition" => outage.condition,
        }.compact
      end

      sync_affected_entity_membership(event, affected_entity, outage)

      OntologySyncSupport.upsert_evidence_link(event, outage, evidence_role: "outage_record", confidence: OntologySyncSupport.normalized_confidence(outage.score))
      event
    end

    private

    # A flights or ships row is a sighting, not an identity. The pollers purge
    # rows untouched for five minutes and re-insert on the next sweep, so one
    # aircraft cycles through many row ids a day while its entity — keyed on the
    # durable icao24/mmsi — outlives all of them. upsert_link keys on
    # linkable_id, so every cycle left the previous link behind pointing at a
    # deleted row: 20.9M links for 267k aircraft, 100% of them dangling, before
    # this was collected. One link per entity is the whole truth here; the
    # superseded ones carry no history worth keeping.
    def supersede_sighting_links(entity, role:, linkable_type:, current_id:)
      OntologyEntityLink
        .where(ontology_entity_id: entity.id, role: role, linkable_type: linkable_type)
        .where.not(linkable_id: current_id)
        .delete_all
    end

    def batch_relation(target, ids:, cursor:, batch_size:, updated_after:)
      relation = case target.to_s
      when "flights"
        Flight.order(:id)
      when "ships"
        Ship.order(:id)
      when "outages"
        InternetOutage.order(:id)
      else
        raise ArgumentError, "unknown operational ontology sync target: #{target}"
      end

      relation = relation.where(id: ids) if ids.present?
      parsed_updated_after = parse_time(updated_after)
      relation = relation.where("updated_at >= ?", parsed_updated_after) if parsed_updated_after
      relation = relation.where("id > ?", cursor.to_i).limit(batch_size) if ids.blank?
      relation
    end

    def sync_record(target, record)
      case target.to_s
      when "flights"
        sync_flight(record)
      when "ships"
        sync_ship(record)
      when "outages"
        sync_outage(record)
      else
        raise ArgumentError, "unknown operational ontology sync target: #{target}"
      end
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def sync_affected_entity_membership(event, affected_entity, outage)
      membership_id = nil

      if affected_entity.present?
        membership = OntologySyncSupport.persist_upsert(
          OntologyEventEntity,
          ontology_event: event,
          ontology_entity: affected_entity,
          role: "affected_party"
        ) do |record|
          record.confidence = OntologySyncSupport.normalized_confidence(outage.score)
          record.metadata = { "datasource" => outage.datasource }.compact
        end
        membership_id = membership.id
      end

      stale_scope = event.ontology_event_entities.where(role: "affected_party")
      stale_scope = stale_scope.where.not(id: membership_id) if membership_id
      stale_scope.delete_all
    end

    def sync_outage_entity(outage)
      return if outage.entity_name.blank? && outage.entity_code.blank?

      entity_type = outage_place_entity?(outage) ? PLACE_ENTITY_TYPE : ORGANIZATION_ENTITY_TYPE
      key = if entity_type == PLACE_ENTITY_TYPE
        "place:outage:#{outage.entity_code.to_s.downcase.presence || OntologySyncSupport.slugify(outage.entity_name)}"
      else
        "organization:outage:#{outage.entity_code.to_s.downcase.presence || OntologySyncSupport.slugify(outage.entity_name)}"
      end

      OntologySyncSupport.upsert_entity(
        canonical_key: key,
        entity_type: entity_type,
        canonical_name: outage.entity_name.presence || outage.entity_code,
        country_code: entity_type == PLACE_ENTITY_TYPE ? outage.entity_code.to_s.first(2).upcase.presence : nil,
        metadata: {
          "datasource" => outage.datasource,
          "entity_type" => outage.entity_type,
          "entity_code" => outage.entity_code,
        }.compact
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, outage.entity_name, alias_type: "official")
        OntologySyncSupport.upsert_alias(entity, outage.entity_code, alias_type: "code")
        OntologySyncSupport.upsert_link(entity, outage, role: "affected_entity", method: "operational_ontology_sync_v1")
      end
    end

    def flight_entity_key(flight)
      return "asset:flight:icao24:#{flight.icao24.downcase}" if flight.icao24.present?
      return "asset:flight:callsign:#{OntologySyncSupport.slugify(flight.callsign)}" if flight.callsign.present?

      "asset:flight:record:#{flight.id}"
    end

    def ship_entity_key(ship)
      return "asset:ship:mmsi:#{ship.mmsi}" if ship.mmsi.present?
      return "asset:ship:name:#{OntologySyncSupport.slugify(ship.name)}" if ship.name.present?

      "asset:ship:record:#{ship.id}"
    end

    def outage_event_key(outage)
      "event:internet-outage:#{outage.external_id.presence || outage.id}"
    end

    def outage_place_entity?(outage)
      %w[country region state province territory city].include?(outage.entity_type.to_s.downcase) ||
        outage.entity_code.to_s.length == 2
    end

    def country_code_for_name(name)
      return nil if name.blank?

      return "US" if name == "United States"
      return "GB" if name == "United Kingdom"

      nil
    end
  end
end
