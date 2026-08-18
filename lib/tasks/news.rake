namespace :news do
  desc "Re-fold cluster text_tokens to the current stem so live clusters stay matchable (DRY_RUN=1)"
  # NewsStoryClusterer::MINIMUM_TEXT_SIMILARITY compares an incoming article's
  # tokens against the bag stored on the cluster. Changing how tokens are folded
  # changes both sides -- but only the incoming side is recomputed per run, and
  # the stored side is rewritten only when recalculate_cluster! next touches
  # that cluster. Between the two, every comparison is stemmed-against-unstemmed,
  # scores near zero, and the floor sends every article to a fresh singleton.
  # This closes that window by re-folding the stored bags in place.
  task retokenize_clusters: :environment do
    dry_run = ENV["DRY_RUN"].present?
    scope = NewsStoryCluster.where.not(metadata: nil)
    total = scope.count
    changed = 0
    examined = 0

    scope.find_each(batch_size: 500) do |cluster|
      stored = Array(cluster.metadata["text_tokens"])
      next if stored.empty?

      examined += 1
      folded = NewsStoryClusterer.send(:normalized_tokens, stored.join(" ")).to_a
      next if folded.sort == stored.sort

      changed += 1
      next if dry_run

      cluster.update_columns(
        metadata: cluster.metadata.merge("text_tokens" => folded),
        updated_at: Time.current
      )
    end

    puts "clusters: #{total}, with tokens: #{examined}, re-folded: #{changed}#{' (dry run)' if dry_run}"
  end

  desc "Embed article headlines for the clusterer's cosine gate (SCOPE=all, LIMIT=n, THREADS=4)"
  # Only in-scope, titled articles by default: out_of_scope rows never reach the
  # clusterer, so embedding them buys nothing and is 45k of the 62k corpus.
  #
  # Idempotent through title_embedding_digest, which covers the model, the width
  # and the prepared text. Changing any of the three re-embeds; re-running after
  # a clean pass does nothing.
  task backfill_headline_embeddings: :environment do
    scope = NewsArticle.where.not(title: nil)
    scope = scope.where.not(content_scope: "out_of_scope") unless ENV["SCOPE"] == "all"
    scope = scope.limit(Integer(ENV["LIMIT"])) if ENV["LIMIT"].present?

    total = scope.count
    tag = NewsHeadlineEmbeddingService.model_tag
    puts "corpus: #{total} articles, model #{tag}"

    embedded = 0
    skipped = 0
    failed = 0
    started = Time.current

    scope.select(:id, :title, :title_embedding_digest).find_in_batches(batch_size: NewsHeadlineEmbeddingService::BATCH_SIZE) do |batch|
      pending = batch.reject do |article|
        current = article.title_embedding_digest.present? &&
          article.title_embedding_digest == NewsHeadlineEmbeddingService.digest_for(article.title)
        skipped += 1 if current
        current
      end
      next if pending.empty?

      vectors = NewsHeadlineEmbeddingService.embed(pending.map(&:title))
      rows = pending.each_with_index.filter_map do |article, index|
        vector = vectors[index]
        next (failed += 1) && nil if vector.blank?

        [ article.id, vector, article.title ]
      end

      NewsArticle.transaction do
        rows.each do |id, vector, title|
          NewsArticle.where(id: id).update_all(
            title_embedding: "{#{vector.join(',')}}",
            title_embedding_model: tag,
            title_embedding_digest: NewsHeadlineEmbeddingService.digest_for(title),
            updated_at: Time.current
          )
        end
      end
      embedded += rows.size

      done = embedded + skipped + failed
      print "\r  #{done}/#{total}  (#{(done / [ Time.current - started, 0.001 ].max).round} rows/s)"
    end

    puts "\nembedded: #{embedded}, already current: #{skipped}, failed: #{failed}"
    puts "coverage: #{NewsArticle.where.not(title_embedding: nil).count} of #{total}"
  end

  desc "Classify claims into a real event family (DRY_RUN=1, LIMIT=n, SCOPE=all|fallback)"
  # The `general` fallthrough holds more claims than the clusterer accepts in
  # total. This is the arm that opens it; run it with DRY_RUN=1 first and read
  # the none-rate before letting it write. A resolver that assigns nearly
  # everything has stopped classifying.
  task resolve_claim_types: :environment do
    dry_run = ENV["DRY_RUN"].present?
    limit = ENV["LIMIT"].present? ? Integer(ENV["LIMIT"]) : nil
    scope = (ENV["SCOPE"].presence || "fallback").to_sym

    pending = NewsClaimTypeBackfillService.candidates(scope: scope).count
    puts "catalog: #{NewsClaimTypeResolver::CATALOG.size} event kinds, model #{NewsClaimTypeResolver::MODEL}"
    puts "scope: #{scope} -- #{pending} claims to classify"
    puts "(dry run -- nothing will be written)" if dry_run

    started = Time.current
    stats = NewsClaimTypeBackfillService.run(dry_run: dry_run, limit: limit, scope: scope)
    considered = stats[:candidates].to_i

    puts "\nconsidered: #{considered} in #{(Time.current - started).round}s"
    puts "assigned:   #{stats[:assigned].to_i}#{percent_of(stats[:assigned], considered)}"
    puts "none:       #{stats[:none].to_i}#{percent_of(stats[:none], considered)}"
    # Never a silent zero. NewsClusterAdjudicator lost 16% of an arm to
    # connection failures that nothing counted, and the arm looked fine.
    puts "unreachable: #{stats[:unreachable].to_i}#{percent_of(stats[:unreachable], considered)}"

    stats[:families].each { |family, count| puts "  #{family.ljust(15)} #{count}" }
    puts "\nrevert with: NewsClaimTypeBackfillService.revert" unless dry_run || stats[:assigned].to_i.zero?
  end

  def percent_of(count, total)
    return "" unless total.to_i.positive?

    " (#{((count.to_f / total) * 100).round(1)}%)"
  end
end
