module NewsDedupable
  extend ActiveSupport::Concern

  private

  # Dedup records by normalized title similarity.
  # Uses both Jaccard (word overlap) and containment (subset check) to catch
  # paraphrases AND headline extensions ("X happens" vs "X happens, 50 dead").
  def dedup_by_title(records, existing_titles: [])
    seen = existing_titles.dup
    records.select do |record|
      title = record[:title]
      if title.blank?
        true
      else
        words = normalize_title(title)
        duplicate = seen.any? { |s| similar?(s, words) }
        seen << words unless duplicate
        !duplicate
      end
    end
  end

  def normalize_title(title)
    title.downcase.gsub(/[^a-z0-9\s]/, "").split.reject { |w| w.length < 2 }.to_set
  end

  # Assign story_cluster_id to records by grouping similar titles.
  # Uses looser thresholds than dedup (Jaccard 0.4 / containment 0.7) so articles
  # about the same event from different sources get the same cluster ID.
  def assign_clusters(records)
    clusters = [] # array of { words: Set, id: String }

    # Load existing clusters from recent DB records
    NewsEvent.where("published_at > ?", 48.hours.ago)
      .where.not(story_cluster_id: nil)
      .pluck(:title, :story_cluster_id)
      .each do |title, cluster_id|
        next if title.blank?
        words = normalize_title(title)
        existing = clusters.find { |c| c[:id] == cluster_id }
        if existing.nil?
          clusters << { words: words, id: cluster_id }
        end
      end

    records.each do |record|
      title = record[:title]
      if title.blank?
        record[:story_cluster_id] = nil
        next
      end

      words = normalize_title(title)
      match = clusters.find { |c| cluster_similar?(c[:words], words) }

      if match
        record[:story_cluster_id] = match[:id]
      else
        cluster_id = Digest::MD5.hexdigest(words.sort.join(" "))[0, 12]
        record[:story_cluster_id] = cluster_id
        clusters << { words: words, id: cluster_id }
      end
    end

    records
  end

  # Two-pronged similarity: Jaccard for general overlap, containment for subset detection.
  # Short titles (< 5 words) use a stricter Jaccard threshold since small word sets
  # produce inflated scores from minor overlaps.
  def similar?(set_a, set_b)
    similarity_scores(set_a, set_b, jaccard_base: 0.5, jaccard_short: 0.65, containment_min: 0.8)
  end

  # Looser thresholds for clustering (same story, different wording).
  # No stemming, so "kills" vs "killing" won't match — compensate with lower thresholds.
  def cluster_similar?(set_a, set_b)
    similarity_scores(set_a, set_b, jaccard_base: 0.3, jaccard_short: 0.45, containment_min: 0.55)
  end

  def similarity_scores(set_a, set_b, jaccard_base:, jaccard_short:, containment_min:)
    return false if set_a.empty? || set_b.empty?

    intersection = (set_a & set_b).size.to_f
    union = (set_a | set_b).size.to_f
    smaller = [set_a.size, set_b.size].min.to_f

    jaccard = intersection / union
    containment = intersection / smaller

    return true if containment >= containment_min && intersection >= 3

    threshold = smaller < 5 ? jaccard_short : jaccard_base
    jaccard > threshold
  end
end
