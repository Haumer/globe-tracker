namespace :ontology do
  desc "Score the ontology (DAYS=30). Prints coverage, connectivity and the anchor-precision guard."
  task score: :environment do
    days = ENV.fetch("DAYS", 30).to_i
    result = OntologyScorecardService.call(since: days.days.ago)
    metrics = result.metrics

    puts
    puts "Ontology scorecard - #{days}d window, generated #{result.generated_at.utc.iso8601}"
    puts "=" * 78

    yield_metric = metrics.fetch(:ingest_yield)
    stages = yield_metric.fetch(:stages)
    puts
    puts "1. INGEST YIELD                                        #{format('%5.1f%%', yield_metric.fetch(:value))}"
    previous = stages.fetch(:articles)
    stages.each do |name, count|
      drop = previous.zero? || count == previous ? "" : format("  (drops %.1f%%)", 100.0 - (100.0 * count / previous))
      puts format("     %-18s %8d%s", name, count, drop)
      previous = count
    end

    cross = metrics.fetch(:cross_domain_link_rate)
    puts
    puts "2. CROSS-DOMAIN LINK RATE                              #{format('%5.1f%%', cross.fetch(:value))}"
    puts format("     %d of %d events reach a non-news object", cross.fetch(:count), cross.fetch(:total))
    cross.fetch(:by_target).first(8).each { |type, count| puts format("     %-20s %8d", type, count) }

    situation = metrics.fetch(:situation_coverage)
    puts
    puts "3. SITUATION COVERAGE                                  #{format('%5.1f%%', situation.fetch(:value))}"
    puts format("     %d of %d conflict clusters under a named umbrella", situation.fetch(:count), situation.fetch(:total))
    situation.fetch(:by_theater).first(6).each { |name, count| puts format("     %-28s %6d", name, count) }

    anchor = metrics.fetch(:anchor_precision)
    puts
    puts "4. ANCHOR PRECISION  (the guard on 1-3)                #{format('%5.1f%%', anchor.fetch(:value))}"
    puts format("     %d of %d event places are not a publisher", anchor.fetch(:count), anchor.fetch(:total))

    frag = metrics.fetch(:fragmentation)
    puts
    puts "5. FRAGMENTATION (proxy)                               #{format('%5.1f%%', frag.fetch(:value))}"
    puts format("     %d redundant clusters over %d distinct events", frag.fetch(:count), frag.fetch(:distinct_events))

    puts
    puts "6. LIVENESS"
    metrics.fetch(:liveness).sort_by { |_, data| -(data[:age_hours] || 0) }.each do |derived_by, data|
      age = data[:age_hours] ? format("%9.1fh", data[:age_hours]) : "    never"
      puts format("     %-38s %8d rows  %s", derived_by, data.fetch(:count), age)
    end
    puts
  end

  desc "Re-anchor existing ontology events through NewsPlaceResolver (DRY_RUN=1 to preview)"
  task repair_places: :environment do
    dry_run = ENV["DRY_RUN"].present?
    scope = OntologyEvent.where.not(primary_story_cluster_id: nil).includes(:primary_story_cluster)
    stats = Hash.new(0)

    scope.find_each do |event|
      cluster = event.primary_story_cluster
      next unless cluster

      resolved = NewsOntologySyncService.send(:resolve_cluster_place, cluster)
      before = event.place_entity_id

      after = if resolved.none?
        nil
      elsif resolved.country?
        OntologyEntity.find_by(entity_type: "country", country_code: resolved.country_code.to_s.upcase)&.id
      elsif dry_run
        # Look the place up rather than syncing it. sync_place_entity upserts,
        # so calling it here would make DRY_RUN write the very rows it claims
        # not to. A miss just means "would be created".
        OntologyEntity.find_by(
          entity_type: "place",
          canonical_key: "place:#{OntologySyncSupport.slugify(resolved.name)}"
        )&.id
      else
        NewsOntologySyncService.send(:sync_place_entity, cluster)&.id
      end

      stats[:examined] += 1
      next stats[:unchanged] += 1 if before == after

      stats[resolved.none? ? :cleared : (resolved.country? ? :to_country : :to_place)] += 1
      event.update_column(:place_entity_id, after) unless dry_run
    end

    puts(dry_run ? "DRY RUN - nothing written" : "Re-anchored ontology events")
    stats.sort.each { |name, count| puts format("  %-12s %d", name, count) }

    # Places nothing points at any more. Left in place rather than deleted: they
    # are cheap, and a masthead entity with no inbound edges is inert, whereas a
    # delete would cascade into aliases and links that may predate this.
    orphaned = OntologyEntity.where(entity_type: "place")
      .where.not(id: OntologyEvent.select(:place_entity_id).where.not(place_entity_id: nil))
      .count
    puts format("  %-12s %d (left in place, now unreferenced)", "orphaned", orphaned)
  end

  desc "Freeze a contiguous corpus window to a manifest (DAYS=14, OUT=tmp/ontology_corpus.json)"
  task corpus: :environment do
    days = ENV.fetch("DAYS", 14).to_i
    out = ENV.fetch("OUT", Rails.root.join("tmp", "ontology_corpus.json").to_s)
    since = days.days.ago
    now = Time.current

    # Contiguous and unfiltered on purpose. The thing under test is grouping, so
    # a random sample across months separates stories that belong together; and
    # `out_of_scope` is 70% of the data and the largest gate, so excluding it
    # would make recall unmeasurable.
    articles = NewsArticle.where(fetched_at: since..now).pluck(:id, :content_scope, :hydration_status)
    strata = articles.group_by { |_id, scope, hydration| [ scope, hydration == "hydrated" ? "body" : "headline" ] }

    manifest = {
      "generated_at" => now.utc.iso8601,
      "window" => { "since" => since.utc.iso8601, "until" => now.utc.iso8601 },
      "article_count" => articles.size,
      "strata" => strata.transform_keys { |scope, text| "#{scope}/#{text}" }.transform_values(&:size),
      "article_ids" => articles.map(&:first).sort,
    }

    File.write(out, JSON.pretty_generate(manifest))
    puts "Froze #{articles.size} articles (#{days}d) to #{out}"
    manifest.fetch("strata").sort_by { |_, count| -count }.each do |name, count|
      puts format("  %-28s %6d  %5.1f%%", name, count, 100.0 * count / articles.size)
    end
  end
end
