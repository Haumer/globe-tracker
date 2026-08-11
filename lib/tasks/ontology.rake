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

  desc "Populate ontology_events.latitude/longitude from NewsPlaceResolver (DRY_RUN=1 to preview)"
  task backfill_event_coordinates: :environment do
    dry_run = ENV["DRY_RUN"].present?
    scope = OntologyEvent.where.not(primary_story_cluster_id: nil).includes(:primary_story_cluster)
    stats = Hash.new(0)

    scope.find_each do |event|
      cluster = event.primary_story_cluster
      next unless cluster

      stats[:examined] += 1
      resolution = NewsOntologySyncService.send(:resolve_cluster_place, cluster)

      # Deliberately narrower than "has a coordinate". A publisher-derived
      # coordinate is precisely the defect NewsPlaceResolver exists to stop, and
      # writing it to an indexed column would make it cheap to query and easy to
      # believe. An event with no coordinate is honest; one sitting on its
      # newspaper is not.
      unless resolution.coordinate_trusted?
        stats[resolution.none? ? :unresolved : :untrusted_coordinate] += 1
        next
      end

      if event.latitude == resolution.latitude && event.longitude == resolution.longitude
        stats[:unchanged] += 1
        next
      end

      stats[:populated] += 1
      next if dry_run

      event.update_columns(latitude: resolution.latitude, longitude: resolution.longitude)
    end

    # Hazard events carry a real observation coordinate on the evidence record
    # they were built from -- a satellite pass or a seismograph, which reports
    # where the thing happened. No publisher gate applies.
    OntologyEvent.where("canonical_key LIKE ?", "event:%").includes(:place_entity).find_each do |event|
      stats[:hazard_examined] += 1
      place = event.place_entity
      lat = place&.metadata&.dig("latitude")
      lng = place&.metadata&.dig("longitude")

      # Outage events anchor to a country-shaped place. A country has no point,
      # and inventing a centroid for one would be a coordinate nobody measured.
      if lat.blank? || lng.blank?
        stats[:hazard_no_point] += 1
        next
      end

      if event.latitude.present?
        stats[:hazard_unchanged] += 1
        next
      end

      stats[:hazard_populated] += 1
      next if dry_run

      event.update_columns(latitude: lat.to_f, longitude: lng.to_f)
    end

    puts(dry_run ? "DRY RUN - nothing written" : "Backfilled event coordinates")
    stats.sort.each { |name, count| puts format("  %-22s %6d", name, count) }

    # Reported against live events, not the whole table. 83% of ontology_events
    # are tombstones whose story cluster was purged by retention: they cannot be
    # re-resolved because the cluster they would resolve from is gone. Counting
    # them would make coverage a statement about how much dead weight the table
    # carries rather than about how many real events are addressable.
    live = OntologyEvent.where("primary_story_cluster_id IS NOT NULL OR canonical_key LIKE ?", "event:%")
    live_total = live.count
    live_coords = live.where.not(latitude: nil).count + (dry_run ? stats[:populated] + stats[:hazard_populated] : 0)
    puts
    puts format("  %-22s %6d of %6d live events (%.1f%%)", "carry coordinates", live_coords, live_total, 100.0 * live_coords / live_total)
    puts format("  %-22s %6d of %6d all events  (%.1f%%)", "", live_coords, OntologyEvent.count, 100.0 * live_coords / OntologyEvent.count)
  end

  # Phase 1.3. Hand-written on purpose. There are twelve corridors, the plan asks
  # for exactly this ("Jizan"/"JAZAN", "Bab al-"/"Bab el-"), and deriving short
  # forms mechanically goes wrong in ways no rule catches cheaply: stripping the
  # geographic words off "Taiwan Strait" yields "Taiwan", which then matches every
  # story about the island -- and Taiwan is absent from the 238 country entities,
  # so the country guard cannot catch it either. "Cape Horn" yields "Horn", which
  # would take the Horn of Africa. Those three are deliberately left with no short
  # form; a missed link costs recall, a wrong one costs precision everywhere.
  CORRIDOR_ALIASES = {
    "corridor:chokepoint:hormuz" => ["Hormuz", "Straits of Hormuz"],
    "corridor:chokepoint:bab_el_mandeb" => ["Bab el-Mandeb", "Bab al-Mandab", "Bab al-Mandeb", "Mandeb", "Mandab"],
    "corridor:chokepoint:suez" => ["Suez"],
    "corridor:chokepoint:malacca" => ["Malacca", "Straits of Malacca"],
    "corridor:chokepoint:bosphorus" => ["Bosphorus", "Bosporus"],
    "corridor:chokepoint:gibraltar" => ["Gibraltar"],
    "corridor:chokepoint:panama" => ["Panama Canal"],
    "corridor:chokepoint:mozambique" => ["Mozambique Channel"],
    "corridor:chokepoint:danish_straits" => ["Danish Straits"],
    "corridor:chokepoint:taiwan_strait" => ["Taiwan Strait"],
    "corridor:chokepoint:cape" => ["Cape of Good Hope"],
    "corridor:chokepoint:cape_horn" => ["Cape Horn"],
  }.freeze

  desc "Seed reviewed short-form aliases for the 12 corridor entities (DRY_RUN=1 to preview)"
  task seed_corridor_aliases: :environment do
    dry_run = ENV["DRY_RUN"].present?
    stats = Hash.new(0)

    CORRIDOR_ALIASES.each do |canonical_key, names|
      entity = OntologyEntity.find_by(canonical_key: canonical_key)
      unless entity
        puts format("  %-36s MISSING", canonical_key)
        stats[:missing_entity] += 1
        next
      end

      names.each do |name|
        if OntologyEntityAlias.exists?(ontology_entity: entity, name: name)
          stats[:already_present] += 1
          next
        end

        stats[:created] += 1
        next if dry_run

        OntologySyncSupport.upsert_alias(entity, name, alias_type: "short_form")
      end
      puts format("  %-22s %s", entity.canonical_name, names.join(", "))
    end

    puts
    puts(dry_run ? "DRY RUN - nothing written" : "Seeded corridor aliases")
    stats.sort.each { |name, count| puts format("  %-18s %4d", name, count) }
  end

  desc "Measure registry name resolution against the eval sets (DAYS=21)"
  task measure_registry_links: :environment do
    days = ENV.fetch("DAYS", 21).to_i
    clusters = NewsStoryCluster.where("last_seen_at >= ?", days.days.ago).pluck(:id, :canonical_title)
    index = RegistryNameIndex.new

    puts "Registry name index"
    puts format("  usable surfaces   %7d", index.usable.size)
    index.rejections.sort_by { |_, count| -count }.each { |name, count| puts format("    rejected %-24s %6d", name, count) }

    matches = clusters.to_h { |id, title| [id, index.match(title)] }
    linked = matches.count { |_, found| found.any? }
    confident = matches.count { |_, found| found.any?(&:confident?) }

    puts
    puts format("  clusters              %6d", clusters.size)
    puts format("  with any match        %6d (%.1f%%)", linked, 100.0 * linked / clusters.size)
    puts format("  with confident match  %6d (%.1f%%)", confident, 100.0 * confident / clusters.size)

    puts
    puts "Eval sets"
    hormuz = clusters.select { |_, title| title.to_s.downcase.include?("hormuz") }
    hit = hormuz.count { |id, _| matches[id].any? { |m| m.entity_name.to_s.downcase.include?("hormuz") } }
    puts format("  Hormuz corridor   %3d of %3d (%.0f%%)", hit, hormuz.size, 100.0 * hit / [hormuz.size, 1].max)

    jazan = clusters.select { |_, title| title.to_s.downcase.match?(/jazan|jizan/) }
    hit = jazan.count { |id, _| matches[id].any? { |m| m.entity_name.to_s.upcase.match?(/JAZAN|JIZAN/) } }
    puts format("  Jazan asset       %3d of %3d (%.0f%%)", hit, jazan.size, 100.0 * hit / [jazan.size, 1].max)

    puts
    puts "Matches by entity type"
    matches.values.flatten.group_by(&:entity_type).transform_values(&:size)
      .sort_by { |_, count| -count }.each { |type, count| puts format("  %-18s %5d", type, count) }

    puts
    puts "Confident matches, most frequent"
    matches.values.flatten.select(&:confident?).map { |m| "#{m.entity_type}:#{m.entity_name}" }
      .tally.sort_by { |_, count| -count }.first(15)
      .each { |name, count| puts format("  %-44s %4d", name.first(42), count) }
  end

  desc "Delete entity links whose polymorphic parent is gone (DRY_RUN=1 to preview, WINDOW=250000)"
  task collect_dangling_links: :environment do
    dry_run = ENV["DRY_RUN"].present?
    window = ENV.fetch("WINDOW", 250_000).to_i

    # PurgeStaleDataJob sweeps these hourly, but it caps each table at 1M rows
    # per run to stay off the write path. That is the right shape for steady
    # state and the wrong one for draining an accumulated backlog, which is what
    # this task is for: it walks the id space in windows so every statement is
    # index-backed and short, rather than opening one transaction over the lot.
    totals = Hash.new(0)

    OntologyEntityLink.distinct.pluck(:linkable_type).compact.sort.each do |type_name|
      owner = type_name.safe_constantize
      # Same call as the hourly sweep: deleting rows on behalf of a class we can
      # no longer resolve is not a decision this task should make.
      unless owner.respond_to?(:primary_key)
        puts format("  %-18s skipped (class missing)", type_name)
        next
      end

      scope = OntologyEntityLink.where(linkable_type: type_name)
      min_id, max_id = scope.pick(Arel.sql("MIN(id), MAX(id)"))
      next if min_id.nil?

      deleted = 0
      cursor = min_id
      while cursor <= max_id
        batch = scope.where(id: cursor...(cursor + window)).where.not(linkable_id: owner.select(:id))
        deleted += dry_run ? batch.count : batch.delete_all
        cursor += window
      end

      totals[type_name] = deleted
      puts format("  %-18s %10d dangling", type_name, deleted) if deleted.positive?
    end

    remaining = OntologyEntityLink.count
    puts
    puts(dry_run ? "DRY RUN - nothing written" : "Collected dangling entity links")
    puts format("  %-18s %10d", "total", totals.values.sum)
    puts format("  %-18s %10d", dry_run ? "would remain" : "remaining", remaining - (dry_run ? totals.values.sum : 0))
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
