# Retires the "places" that were never places.
#
# The old cluster sync anchored events to `NewsEvent#name` -- the publisher --
# which is how mastheads became the most common places in the graph, and how
# they acquired coordinates: last-writer-wins metadata let any co-mentioned
# story drag their pin ("Washington Post" ended up in the Strait of Hormuz).
# The writer no longer mints these, so what remains is legacy data, plus the
# wildfire detections a bulk import once registered as places.
#
# Deliberately conservative: an entity is removed only when its name matches a
# known publisher (news_sources or the source entities the sync maintains) or
# the fire-detection pattern. Anything else -- including oddities like personal
# bylines -- is left for a human, and reported rather than guessed at.
# Dry-run by default; nothing is deleted unless apply: true.
class PlaceEntityCleanupService
  FIRE_PATTERN = /\Aextreme fire fc_/i

  # Feed-name prefixes that decorate a masthead without changing what it is:
  # "GN: Jerusalem Post" is still the Jerusalem Post.
  STRIP_PREFIXES = /\A(?:gn|rss|feed)\s+/

  Report = Struct.new(:mastheads, :fires, :kept, :events_detached, :applied, :samples, keyword_init: true)

  class << self
    def call(apply: false)
      places = OntologyEntity.where(entity_type: "place")
      total = places.count
      publisher_names = known_publisher_names

      masthead_ids = []
      fire_ids = []
      places.pluck(:id, :canonical_name).each do |id, name|
        if name.to_s.match?(FIRE_PATTERN)
          fire_ids << id
        elsif publisher_names.include?(comparable_name(name))
          masthead_ids << id
        end
      end

      doomed_ids = masthead_ids + fire_ids
      samples = OntologyEntity.where(id: doomed_ids.first(10)).pluck(:canonical_name)
      detached = OntologyEvent.where(place_entity_id: doomed_ids).count
      if apply && doomed_ids.any?
        OntologyEntity.transaction do
          OntologyEvent.where(place_entity_id: doomed_ids).update_all(place_entity_id: nil)
          # The entity destroy delete_alls its relationships, which would strand
          # (then violate) the evidence rows pointing at them -- clear the whole
          # chain explicitly, evidence first.
          relationship_ids = OntologyRelationship
            .where(source_node_type: "OntologyEntity", source_node_id: doomed_ids)
            .or(OntologyRelationship.where(target_node_type: "OntologyEntity", target_node_id: doomed_ids))
            .pluck(:id)
          OntologyRelationshipEvidence.where(ontology_relationship_id: relationship_ids).delete_all
          OntologyRelationship.where(id: relationship_ids).delete_all
          OntologyEntity.where(id: doomed_ids).find_each(&:destroy!)
        end
      end

      Report.new(
        mastheads: masthead_ids.size,
        fires: fire_ids.size,
        kept: total - doomed_ids.size,
        events_detached: detached,
        applied: apply,
        samples: samples
      )
    end

    private

    # Publishers as the pipeline knows them: the news_sources table and the
    # source entities the ontology sync maintains from it, names and domains.
    def known_publisher_names
      names = NewsSource.pluck(:name, :publisher_domain).flatten +
        OntologyEntity.where(entity_type: "source").pluck(:canonical_name)
      names.filter_map { |name| comparable_name(name) }.to_set
    end

    def comparable_name(name)
      normalized = Place.normalize_name(name)
      return nil if normalized.blank?

      normalized.sub(STRIP_PREFIXES, "").presence
    end
  end
end
