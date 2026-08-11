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
end
