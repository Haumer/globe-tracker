# Writes NewsClaimTypeResolver's decisions back onto the claims the rules gave
# up on.
#
# Only event_family and event_type change. Nothing touches confidence, trust or
# provenance, and that restraint is the point: this is one arm of a measured
# comparison, and an arm that moves four things at once cannot be attributed to
# any of them. The claim either clears NewsStoryClusterer#build_payload or it
# does not, and family plus type is the whole of what decides that.
#
# Every row it writes is marked `extraction_method: "model"` and carries the
# values the rules originally produced under metadata["resolved_from"], so the
# arm is reversible with a single scope and the two populations stay separable
# forever after.
class NewsClaimTypeBackfillService
  EXTRACTION_METHOD = "model".freeze
  EXTRACTION_VERSION = "claim_type_resolver_v1".freeze
  FALLBACK_FAMILY = "general".freeze

  class << self
    # dry_run reports exactly what a real run would write without writing it, so
    # the none-rate can be read before rows move. limit samples.
    #
    # scope: :fallback classifies only what the rules gave up on. :all classifies
    # every claim, because the rules are wrong more often than they are right --
    # 200 rule-matched claims judged, 56.5% misfired, against ~70% correct for
    # the model on the harder residue the rules could not label at all. A wrong
    # label is worse than none: event_type_score returns 0.0 for incompatible
    # types, so a misfire actively blocks a correct merge where `general` merely
    # dropped the article.
    def run(dry_run: false, limit: nil, scope: :fallback,
            batch_size: NewsClaimTypeResolver::BATCH_SIZE * 8, client: nil)
      stats = Hash.new(0)
      stats[:families] = Hash.new(0)
      remaining = limit

      candidates(limit: limit, scope: scope).find_in_batches(batch_size: batch_size) do |batch|
        batch = batch.first(remaining) if remaining
        break if batch.empty?

        process(batch, stats, dry_run: dry_run, client: client)

        if remaining
          remaining -= batch.size
          break if remaining <= 0
        end
      end

      stats[:families] = stats[:families].sort_by { |_family, count| -count }.to_h
      stats
    end

    # Undo. Restores what the rules produced from the audit the write left
    # behind, so a bad arm costs a rake task rather than a database restore.
    def revert
      reverted = 0

      NewsClaim.where(extraction_method: EXTRACTION_METHOD, extraction_version: EXTRACTION_VERSION)
        .find_each do |claim|
          original = claim.metadata.to_h["resolved_from"]
          next unless original.is_a?(Hash) && original["event_family"].present?

          claim.update_columns(
            event_family: original["event_family"],
            event_type: original["event_type"],
            extraction_method: original["extraction_method"] || "heuristic",
            extraction_version: original["extraction_version"] || "headline_summary_rules_v2",
            metadata: claim.metadata.to_h.except("resolved_from", "resolved_basis"),
            updated_at: Time.current
          )
          reverted += 1
        end

      { reverted: reverted }
    end

    # Restricted to articles that could still reach a cluster. An out_of_scope
    # article is dropped by build_payload before family is ever consulted, so
    # classifying one spends a model call on a row that cannot move.
    #
    # Rows this version already resolved are excluded either way, so a re-run
    # costs nothing and the job can be scheduled without a cursor.
    def candidates(limit: nil, scope: :fallback)
      relation = NewsClaim
        .joins(:news_article)
        .where.not(news_articles: { content_scope: "out_of_scope" })
        .where.not(news_articles: { title: nil })
        .where.not(extraction_method: EXTRACTION_METHOD, extraction_version: EXTRACTION_VERSION)
        .order(:id)
      relation = relation.where(event_family: FALLBACK_FAMILY) if scope.to_sym == :fallback
      limit ? relation.limit(limit) : relation
    end

    private

    def process(batch, stats, dry_run:, client:)
      titles = NewsArticle.where(id: batch.map(&:news_article_id)).pluck(:id, :title).to_h
      # A claim whose article lost its title between the scope query and here has
      # nothing to classify. Dropping it keeps the resolver's input and output
      # the same length, which is what lets them be zipped safely below.
      pairs = batch.filter_map do |claim|
        title = titles[claim.news_article_id]
        [ claim, title ] if title.present?
      end
      return if pairs.empty?

      assignments = NewsClaimTypeResolver.call(headlines: pairs.map(&:last), client: client)

      pairs.zip(assignments).each do |(claim, _title), assignment|
        stats[:candidates] += 1

        # Not reached is not a decision. Leaving the claim untouched means a run
        # of connection failures shows up as a count instead of quietly
        # restoring the pre-model behaviour on exactly the rows the model exists
        # to judge -- which is how 16% of NewsClusterAdjudicator's first arm
        # disappeared without anything looking wrong.
        unless assignment.called
          stats[:unreachable] += 1
          next
        end

        unless assignment.assigned?
          stats[:none] += 1
          next
        end

        stats[:assigned] += 1
        stats[:families][assignment.event_family] += 1
        next if dry_run

        write(claim, assignment)
      end
    end

    def write(claim, assignment)
      claim.update_columns(
        event_family: assignment.event_family,
        event_type: assignment.event_type,
        extraction_method: EXTRACTION_METHOD,
        extraction_version: EXTRACTION_VERSION,
        metadata: claim.metadata.to_h.merge(
          "resolved_from" => {
            "event_family" => claim.event_family,
            "event_type" => claim.event_type,
            "extraction_method" => claim.extraction_method,
            "extraction_version" => claim.extraction_version,
          },
          "resolved_basis" => assignment.basis,
          "resolved_model" => NewsClaimTypeResolver::MODEL
        ),
        updated_at: Time.current
      )
    end
  end
end
