class NewsOntologySyncService
  DEFAULT_BATCH_SIZE = 200
  BACKFILL_TARGETS = %w[sources actors clusters].freeze
  SOURCE_ENTITY_TYPE = "source".freeze
  ACTOR_ENTITY_TYPE = "actor".freeze
  PLACE_ENTITY_TYPE = "place".freeze

  class << self
    def enqueue_backfill(batch_size: DEFAULT_BATCH_SIZE)
      BACKFILL_TARGETS.each do |target|
        NewsOntologyBatchJob.perform_later(target, { "cursor" => 0, "batch_size" => batch_size })
      end
    end

    def enqueue_for_records(records, batch_size: DEFAULT_BATCH_SIZE)
      return 0 if records.blank?

      source_ids = records.filter_map { |record| fetch(record, :news_source_id) }.uniq
      article_ids = records.filter_map { |record| fetch(record, :news_article_id) }.uniq
      cluster_keys = records.filter_map { |record| fetch(record, :story_cluster_id) }.uniq

      actor_ids = actor_ids_for_articles(article_ids)
      cluster_ids = cluster_keys.any? ? NewsStoryCluster.where(cluster_key: cluster_keys).pluck(:id) : []

      enqueue_ids("sources", source_ids, batch_size: batch_size) +
        enqueue_ids("actors", actor_ids, batch_size: batch_size) +
        enqueue_ids("clusters", cluster_ids, batch_size: batch_size)
    end

    def sync_batch(target, ids: nil, cursor: nil, batch_size: DEFAULT_BATCH_SIZE)
      records = batch_relation(target, ids: ids, cursor: cursor, batch_size: batch_size).to_a
      records.each { |record| sync_record(target, record) }

      {
        records_fetched: records.size,
        records_stored: records.size,
        next_cursor: ids.present? || records.size < batch_size ? nil : records.last.id,
        batch_size: batch_size,
      }
    end

    def sync_all
      NewsSource.find_each { |source| sync_source(source) }
      NewsActor.find_each { |actor| sync_actor(actor) }
      NewsStoryCluster.includes(:lead_news_article, news_articles: { news_claims: { news_claim_actors: :news_actor } }).find_each do |cluster|
        sync_story_cluster(cluster)
      end
    end

    def sync_source(source)
      entity = OntologySyncSupport.upsert_entity(
        canonical_key: "source:#{source.canonical_key}",
        entity_type: SOURCE_ENTITY_TYPE,
        canonical_name: source.name,
        country_code: source.publisher_country,
        metadata: {
          "publisher_domain" => source.publisher_domain,
          "publisher_city" => source.publisher_city,
          "source_kind" => source.source_kind,
        }.compact
      )

      OntologySyncSupport.upsert_alias(entity, source.name, alias_type: "official")
      OntologySyncSupport.upsert_alias(entity, source.publisher_domain, alias_type: "domain") if source.publisher_domain.present?
      OntologySyncSupport.upsert_link(entity, source, role: "publisher", method: "news_ontology_sync_v1")
      entity
    end

    def sync_actor(actor)
      entity = OntologySyncSupport.upsert_entity(
        canonical_key: "actor:#{actor.canonical_key}",
        entity_type: ACTOR_ENTITY_TYPE,
        canonical_name: actor.name,
        country_code: actor.country_code,
        metadata: actor.metadata
      )

      OntologySyncSupport.upsert_alias(entity, actor.name, alias_type: "official")
      OntologySyncSupport.upsert_link(entity, actor, role: actor.actor_type.presence || "actor", method: "news_ontology_sync_v1")
      entity
    end

    def sync_story_cluster(cluster)
      event = OntologyEvent.find_or_initialize_by(canonical_key: "news-story-cluster:#{cluster.cluster_key}")
      event.place_entity = sync_place_entity(cluster)
      event.primary_story_cluster = cluster
      event.event_family = cluster.event_family
      event.event_type = cluster.event_type
      event.status = "active"
      event.verification_status = cluster.verification_status
      event.geo_precision = cluster.geo_precision
      event.confidence = cluster.cluster_confidence
      event.source_reliability = cluster.source_reliability
      event.geo_confidence = cluster.geo_confidence
      event.started_at ||= cluster.first_seen_at
      event.first_seen_at = cluster.first_seen_at
      event.last_seen_at = cluster.last_seen_at
      event.metadata = {
        "canonical_title" => cluster.canonical_title,
        "content_scope" => cluster.content_scope,
        "location_name" => cluster.location_name,
      }.compact
      event.save!

      sync_event_entities(event, cluster)
      sync_evidence_links(event, cluster)
      event
    end

    private

    def fetch(item, key)
      item[key] || item[key.to_s]
    end

    def enqueue_ids(target, ids, batch_size:)
      ids.each_slice(batch_size).count do |batch_ids|
        NewsOntologyBatchJob.perform_later(target, { "ids" => batch_ids })
      end
    end

    def actor_ids_for_articles(article_ids)
      return [] if article_ids.empty?

      NewsClaimActor.joins(:news_claim)
        .where(news_claims: { news_article_id: article_ids })
        .distinct
        .pluck(:news_actor_id)
    end

    def batch_relation(target, ids:, cursor:, batch_size:)
      relation = case target
      when "sources"
        NewsSource.order(:id)
      when "actors"
        NewsActor.order(:id)
      when "clusters"
        NewsStoryCluster.includes(:lead_news_article, news_articles: { news_claims: { news_claim_actors: :news_actor } }).order(:id)
      else
        raise ArgumentError, "unknown news ontology sync target: #{target}"
      end

      relation = relation.where(id: ids) if ids.present?
      relation = relation.where("id > ?", cursor.to_i).limit(batch_size) if ids.blank?
      relation
    end

    def sync_record(target, record)
      case target
      when "sources"
        sync_source(record)
      when "actors"
        sync_actor(record)
      when "clusters"
        sync_story_cluster(record)
      else
        raise ArgumentError, "unknown news ontology sync target: #{target}"
      end
    end

    def sync_place_entity(cluster)
      return if cluster.location_name.blank?

      OntologySyncSupport.upsert_entity(
        canonical_key: "place:#{OntologySyncSupport.slugify(cluster.location_name)}",
        entity_type: PLACE_ENTITY_TYPE,
        canonical_name: cluster.location_name,
        metadata: {
          "latitude" => cluster.latitude,
          "longitude" => cluster.longitude,
          "geo_precision" => cluster.geo_precision,
        }.compact
      ).tap do |entity|
        OntologySyncSupport.upsert_alias(entity, cluster.location_name, alias_type: "official")
      end
    end

    def sync_event_entities(event, cluster)
      actor_roles = aggregated_cluster_actor_roles(cluster)
      existing_memberships = event.ontology_event_entities.index_by { |membership| [membership.ontology_entity_id, membership.role] }
      desired_memberships = {}

      actor_roles.each do |row|
        entity = sync_actor(row.fetch(:actor))
        key = [entity.id, row.fetch(:role)]
        desired_memberships[key] = true

        (existing_memberships[key] || OntologyEventEntity.new(
          ontology_event: event,
          ontology_entity: entity,
          role: row.fetch(:role)
        )).tap do |membership|
          membership.confidence = row.fetch(:confidence)
          membership.metadata = {
            "news_actor_id" => row.fetch(:actor).id,
            "occurrences" => row.fetch(:occurrences),
          }
          membership.save!
        end
      end

      stale_membership_ids = existing_memberships.reject { |key, _membership| desired_memberships[key] }.values.map(&:id)
      OntologyEventEntity.where(id: stale_membership_ids).delete_all if stale_membership_ids.any?
    end

    def sync_evidence_links(event, cluster)
      existing_links = event.ontology_evidence_links.where(evidence_role: %w[primary_cluster lead_article]).index_by do |link|
        [link.evidence_type, link.evidence_id, link.evidence_role]
      end
      desired_links = {}

      desired_links[[cluster.class.name, cluster.id, "primary_cluster"]] = {
        evidence: cluster,
        evidence_role: "primary_cluster",
        confidence: cluster.cluster_confidence,
      }

      if cluster.lead_news_article.present?
        desired_links[[cluster.lead_news_article.class.name, cluster.lead_news_article.id, "lead_article"]] = {
          evidence: cluster.lead_news_article,
          evidence_role: "lead_article",
          confidence: cluster.cluster_confidence,
        }
      end

      desired_links.each_value do |payload|
        OntologySyncSupport.upsert_evidence_link(
          event,
          payload.fetch(:evidence),
          evidence_role: payload.fetch(:evidence_role),
          confidence: payload.fetch(:confidence)
        )
      end

      stale_link_ids = existing_links.reject { |key, _link| desired_links.key?(key) }.values.map(&:id)
      OntologyEvidenceLink.where(id: stale_link_ids).delete_all if stale_link_ids.any?
    end

    def aggregated_cluster_actor_roles(cluster)
      article_ids = cluster.news_story_memberships.pluck(:news_article_id)
      rows = NewsArticle.includes(news_claims: { news_claim_actors: :news_actor })
        .where(id: article_ids)
        .flat_map do |article|
        article.news_claims.flat_map do |claim|
          claim.news_claim_actors.map do |claim_actor|
            {
              actor: claim_actor.news_actor,
              role: claim_actor.role,
              confidence: claim_actor.confidence || claim.confidence || 0.0,
            }
          end
        end
      end

      rows.group_by { |row| [row.fetch(:actor).id, row.fetch(:role)] }.map do |(_, role_rows)|
        {
          actor: role_rows.first.fetch(:actor),
          role: role_rows.first.fetch(:role),
          confidence: role_rows.sum { |row| row.fetch(:confidence) }.to_f / role_rows.size,
          occurrences: role_rows.size,
        }
      end
    end
  end
end
