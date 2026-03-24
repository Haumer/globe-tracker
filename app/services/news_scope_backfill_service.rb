class NewsScopeBackfillService
  class << self
    def run(batch_size: 500)
      article_updates = 0
      event_updates = 0

      NewsArticle.find_in_batches(batch_size: batch_size) do |batch|
        ids_by_scope = Hash.new { |hash, key| hash[key] = [] }

        batch.each do |article|
          scope = NewsScopeClassifier.classify(
            title: article.title,
            summary: article.summary,
            category: article.metadata.to_h["category"]
          )

          if article.content_scope != scope[:content_scope] || article.scope_reason != scope[:scope_reason]
            article.update_columns(
              content_scope: scope[:content_scope],
              scope_reason: scope[:scope_reason],
              updated_at: Time.current
            )
            article_updates += 1
          end

          ids_by_scope[scope[:content_scope]] << article.id
        end

        ids_by_scope.each do |content_scope, article_ids|
          event_updates += NewsEvent.where(news_article_id: article_ids)
            .where("content_scope IS NULL OR content_scope <> ?", content_scope)
            .update_all(content_scope: content_scope)
        end
      end
      event_updates += backfill_orphan_event_scopes(batch_size: batch_size)

      prune_summary = prune_out_of_scope_claims(batch_size: batch_size)
      created_claims = NewsClaimRecorder.backfill_missing(batch_size: batch_size)

      {
        article_updates: article_updates,
        event_updates: event_updates,
        deleted_claims: prune_summary[:deleted_claims],
        deleted_claim_actors: prune_summary[:deleted_claim_actors],
        created_claims: created_claims,
        article_scopes: NewsArticle.group(:content_scope).count,
        event_scopes: NewsEvent.group(:content_scope).count,
        claim_event_families: NewsClaim.group(:event_family).count.sort_by { |_event_family, count| -count }.to_h,
        claim_event_types: NewsClaim.group(:event_type).count.sort_by { |_event_type, count| -count }.to_h,
        claim_coverage_by_scope: claim_coverage_by_scope,
      }
    end

    private

    def prune_out_of_scope_claims(batch_size:)
      deleted_claims = 0
      deleted_claim_actors = 0

      NewsArticle.where(content_scope: "out_of_scope")
        .joins(:news_claims)
        .distinct
        .find_in_batches(batch_size: batch_size) do |batch|
          claim_ids = NewsClaim.where(news_article_id: batch.map(&:id)).pluck(:id)
          next if claim_ids.empty?

          deleted_claim_actors += NewsClaimActor.where(news_claim_id: claim_ids).delete_all
          deleted_claims += NewsClaim.where(id: claim_ids).delete_all
        end

      {
        deleted_claims: deleted_claims,
        deleted_claim_actors: deleted_claim_actors,
      }
    end

    def backfill_orphan_event_scopes(batch_size:)
      updates = 0

      NewsEvent.where(news_article_id: nil).find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |event|
          scope = NewsScopeClassifier.classify(
            title: event.title,
            category: event.category
          )
          next if event.content_scope == scope[:content_scope]

          event.update_columns(content_scope: scope[:content_scope], updated_at: Time.current)
          updates += 1
        end
      end

      updates
    end

    def claim_coverage_by_scope
      NewsArticle.left_outer_joins(:news_claims)
        .group(:content_scope)
        .pluck(
          :content_scope,
          Arel.sql("COUNT(DISTINCT news_articles.id)"),
          Arel.sql("COUNT(DISTINCT CASE WHEN news_claims.id IS NOT NULL THEN news_articles.id END)")
        )
        .each_with_object({}) do |(content_scope, total_articles, claimed_articles), result|
          result[content_scope] = {
            total_articles: total_articles,
            claimed_articles: claimed_articles,
            coverage_pct: if total_articles.to_i.positive?
              ((claimed_articles.to_f / total_articles) * 100).round(1)
            else
              0.0
            end,
          }
        end
    end
  end
end
