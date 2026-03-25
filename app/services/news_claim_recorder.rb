class NewsClaimRecorder
  class << self
    def record_all(items)
      return {} if items.blank?

      now = Time.current
      article_contexts = load_article_contexts(items)
      extracted = items.filter_map do |item|
        article_id = fetch(item, :news_article_id)
        context = article_contexts[article_id] || {}
        title = fetch(item, :title) || context[:title]
        summary = fetch(item, :summary) || context[:summary]
        content_scope = fetch(item, :content_scope) || context[:content_scope]
        next if article_id.blank? || title.blank?
        next if content_scope == "out_of_scope"

        claim = NewsClaimExtractor.extract(title, summary: summary)
        next unless claim

        {
          news_article_id: article_id,
          published_at: normalize_time(fetch(item, :published_at)) || context[:published_at],
          context: context,
          claim: claim,
        }
      end
      return {} if extracted.empty?

      actor_rows = extracted.flat_map { |entry| actor_rows_for(entry[:claim], now) }
      actor_rows_by_key = actor_rows.index_by { |row| row[:canonical_key] }
      NewsActor.upsert_all(actor_rows_by_key.values, unique_by: :canonical_key) if actor_rows_by_key.any?
      actor_ids = NewsActor.where(canonical_key: actor_rows_by_key.keys).pluck(:canonical_key, :id).to_h

      claim_rows = extracted.map do |entry|
        build_claim_row(entry, now)
      end
      NewsClaim.upsert_all(claim_rows, unique_by: :news_article_id) if claim_rows.any?
      claim_ids = NewsClaim.where(news_article_id: claim_rows.map { |row| row[:news_article_id] })
        .pluck(:news_article_id, :id)
        .to_h

      replace_claim_actors(extracted, claim_ids, actor_ids, now)

      claim_ids
    rescue StandardError => e
      Rails.logger.warn("NewsClaimRecorder: #{e.message}")
      {}
    end

    def backfill_missing(batch_size: 500)
      total = 0

      NewsArticle.left_outer_joins(:news_claims)
        .where(news_claims: { id: nil })
        .where.not(content_scope: "out_of_scope")
        .where.not(title: nil)
        .find_in_batches(batch_size: batch_size) do |batch|
          mapping = record_all(batch.map do |article|
            {
              news_article_id: article.id,
              title: article.title,
              published_at: article.published_at,
              content_scope: article.content_scope,
            }
          end)
          total += mapping.size
        end

      total
    end

    def rebuild_all(batch_size: 500)
      total = 0

      NewsArticle.where.not(content_scope: "out_of_scope")
        .where.not(title: nil)
        .find_in_batches(batch_size: batch_size) do |batch|
          article_ids = batch.map(&:id)
          mapping = record_all(batch.map do |article|
            {
              news_article_id: article.id,
              title: article.title,
              summary: article.summary,
              published_at: article.published_at,
              content_scope: article.content_scope,
            }
          end)
          purge_claims_for(article_ids - mapping.keys)
          total += mapping.size
        end

      total
    end

    private

    def load_article_contexts(items)
      article_ids = items.filter_map { |item| fetch(item, :news_article_id) }.uniq
      return {} if article_ids.empty?

      NewsArticle.includes(:news_source, :news_events).where(id: article_ids).each_with_object({}) do |article, contexts|
        event = article.news_events.max_by { |entry| entry.published_at || entry.fetched_at || entry.created_at }
        contexts[article.id] = {
          title: article.title,
          summary: article.summary,
          content_scope: article.content_scope,
          published_at: article.published_at,
          canonical_url: article.canonical_url,
          publisher_name: article.publisher_name,
          publisher_domain: article.publisher_domain,
          source_kind: article.news_source&.source_kind,
          origin_source_name: article.origin_source_name,
          origin_source_kind: article.origin_source_kind,
          origin_source_domain: article.origin_source_domain,
          location_name: event&.name,
          latitude: event&.latitude,
          longitude: event&.longitude,
          event_id: event&.id,
          event_title: event&.title,
        }
      end
    end

    def build_claim_row(entry, now)
      claim = entry[:claim]
      context = entry[:context] || {}
      trust = NewsTrustScorer.claim_attributes(
        source_kind: context[:source_kind],
        publisher_name: context[:publisher_name],
        publisher_domain: context[:publisher_domain],
        origin_source_name: context[:origin_source_name],
        origin_source_kind: context[:origin_source_kind],
        origin_source_domain: context[:origin_source_domain],
        location_name: context[:location_name],
        latitude: context[:latitude],
        longitude: context[:longitude],
        event_id: context[:event_id],
        event_title: context[:event_title],
        canonical_url: context[:canonical_url],
        extraction: claim,
        claim_text: claim[:claim_text],
        published_at: entry[:published_at]
      )

      {
        news_article_id: entry[:news_article_id],
        event_family: claim[:event_family],
        event_type: claim[:event_type],
        claim_text: claim[:claim_text],
        confidence: trust[:confidence],
        extraction_confidence: claim[:extraction_confidence],
        actor_confidence: claim[:actor_confidence],
        event_confidence: claim[:event_confidence],
        geo_confidence: trust[:geo_confidence],
        source_reliability: trust[:source_reliability],
        verification_status: trust[:verification_status],
        geo_precision: trust[:geo_precision],
        extraction_method: claim[:extraction_method],
        extraction_version: claim[:extraction_version],
        published_at: entry[:published_at],
        primary: true,
        metadata: claim[:metadata],
        provenance: trust[:provenance],
        created_at: now,
        updated_at: now,
      }
    end

    def actor_rows_for(claim, now)
      claim[:actors].map do |actor|
        {
          canonical_key: actor[:canonical_key],
          name: actor[:name],
          actor_type: actor[:actor_type],
          country_code: actor[:country_code],
          metadata: {},
          created_at: now,
          updated_at: now,
        }
      end
    end

    def replace_claim_actors(extracted, claim_ids, actor_ids, now)
      resolved_claim_ids = extracted.filter_map { |entry| claim_ids[entry[:news_article_id]] }.uniq
      return if resolved_claim_ids.empty?

      NewsClaimActor.where(news_claim_id: resolved_claim_ids).delete_all

      rows = extracted.flat_map do |entry|
        claim_id = claim_ids[entry[:news_article_id]]
        next [] unless claim_id

        entry[:claim][:actors].each_with_index.filter_map do |actor, index|
          actor_id = actor_ids[actor[:canonical_key]]
          next unless actor_id

          {
            news_claim_id: claim_id,
            news_actor_id: actor_id,
            role: actor[:role],
            position: index,
            confidence: actor[:confidence],
            matched_text: actor[:matched_text].to_s.scrub("")[0...255],
            metadata: {},
            created_at: now,
            updated_at: now,
          }
        end
      end

      NewsClaimActor.insert_all(rows) if rows.any?
    end

    def purge_claims_for(article_ids)
      return if article_ids.empty?

      claim_ids = NewsClaim.where(news_article_id: article_ids).pluck(:id)
      return if claim_ids.empty?

      NewsClaimActor.where(news_claim_id: claim_ids).delete_all
      NewsClaim.where(id: claim_ids).delete_all
    end

    def normalize_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def fetch(item, key)
      item[key] || item[key.to_s]
    end
  end
end
