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

  def assign_clusters(records)
    NewsStoryClusterer.assign_records(records)
  end

  # Two-pronged similarity: Jaccard for general overlap, containment for subset detection.
  # Short titles (< 5 words) use a stricter Jaccard threshold since small word sets
  # produce inflated scores from minor overlaps.
  def similar?(set_a, set_b)
    similarity_scores(set_a, set_b, jaccard_base: 0.5, jaccard_short: 0.65, containment_min: 0.8)
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
