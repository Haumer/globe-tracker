require "digest"
require "set"

class NewsStoryClusterer
  GENERAL_EVENT_TYPES = %w[actor_mention mentioned_relationship].freeze
  CLUSTERABLE_EVENT_FAMILIES = Set.new(%w[
    conflict cyber diplomacy disaster economy humanitarian infrastructure
    justice politics security transport
  ]).freeze
  DEFAULT_WINDOW = 36.hours
  DEFAULT_MAX_DISTANCE_KM = 250.0
  MATCH_THRESHOLD = 0.67
  STRICT_LOCATION_EVENT_TYPES = %w[ground_operation accusation_statement arrest_detention protest].freeze

  FAMILY_WINDOWS = {
    "conflict" => 18.hours,
    "cyber" => 36.hours,
    "diplomacy" => 72.hours,
    "disaster" => 24.hours,
    "economy" => 48.hours,
    "humanitarian" => 48.hours,
    "information" => 24.hours,
    "infrastructure" => 24.hours,
    "justice" => 36.hours,
    "politics" => 48.hours,
    "security" => 18.hours,
    "transport" => 24.hours,
  }.freeze

  FAMILY_MAX_DISTANCE_KM = {
    "conflict" => 175.0,
    "cyber" => 400.0,
    "diplomacy" => 750.0,
    "disaster" => 350.0,
    "economy" => 600.0,
    "humanitarian" => 500.0,
    "information" => 400.0,
    "infrastructure" => 250.0,
    "justice" => 300.0,
    "politics" => 300.0,
    "security" => 200.0,
    "transport" => 250.0,
  }.freeze

  COMPATIBLE_EVENT_GROUPS = [
    %w[airstrike missile_attack],
    %w[negotiation summit agreement diplomatic_contact],
    %w[sanction_action trade_measure],
  ].map(&:to_set).freeze

  class << self
    def assign_records(records)
      return records if records.blank?

      contexts = build_record_contexts(records)
      payloads = load_payloads(contexts)
      assignments = {}

      payloads.sort_by { |payload| payload[:published_at] || payload[:fetched_at] || Time.current }.each do |payload|
        assignments[payload[:news_article_id]] = assign_payload(payload)
      end

      article_ids = contexts.keys
      unassigned_ids = article_ids - assignments.keys
      unassigned_ids.each { |article_id| clear_assignment(article_id) }
      apply_assignments(assignments)

      records.each do |record|
        article_id = fetch(record, :news_article_id)
        assignment = assignments[article_id]
        record[:story_cluster_id] = assignment&.dig(:cluster_key)
      end

      records
    rescue StandardError => e
      Rails.logger.warn("NewsStoryClusterer: #{e.message}")
      records
    end

    def recluster_article(article_or_id)
      article = article_or_id.is_a?(NewsArticle) ? article_or_id : NewsArticle.find_by(id: article_or_id)
      return nil unless article

      context = {
        article.id => {
          published_at: article.published_at,
          fetched_at: article.fetched_at,
          title: article.title,
          summary: article.summary,
          content_scope: article.content_scope,
          source_id: article.news_source_id,
        },
      }
      payload = load_payloads(context).first
      if payload
        assignment = assign_payload(payload)
        apply_assignments(article.id => assignment)
        assignment[:cluster_key]
      else
        clear_assignment(article.id)
        nil
      end
    end

    def rebuild_all(batch_size: 500)
      NewsStoryMembership.delete_all
      NewsStoryCluster.delete_all
      NewsEvent.update_all(story_cluster_id: nil, updated_at: Time.current)

      total = 0
      NewsArticle.where.not(content_scope: "out_of_scope")
        .where.not(title: nil)
        .order(Arel.sql("COALESCE(published_at, fetched_at, created_at) ASC"))
        .find_in_batches(batch_size: batch_size) do |batch|
          batch_records = batch.map do |article|
            event = article.news_events.max_by { |entry| entry.published_at || entry.fetched_at || entry.created_at }
            {
              news_article_id: article.id,
              title: article.title,
              summary: article.summary,
              published_at: article.published_at,
              fetched_at: article.fetched_at,
              content_scope: article.content_scope,
              name: event&.name,
              latitude: event&.latitude,
              longitude: event&.longitude,
              news_source_id: article.news_source_id,
            }
          end
          assign_records(batch_records)
          total += batch_records.size
        end

      total
    end

    private

    def build_record_contexts(records)
      records.each_with_object({}) do |record, contexts|
        article_id = fetch(record, :news_article_id)
        next if article_id.blank?

        existing = contexts[article_id] || {}
        contexts[article_id] = {
          title: fetch(record, :title) || existing[:title],
          summary: fetch(record, :summary) || existing[:summary],
          published_at: normalize_time(fetch(record, :published_at)) || existing[:published_at],
          fetched_at: normalize_time(fetch(record, :fetched_at)) || existing[:fetched_at],
          location_name: fetch(record, :name) || existing[:location_name],
          latitude: fetch(record, :latitude) || existing[:latitude],
          longitude: fetch(record, :longitude) || existing[:longitude],
          content_scope: fetch(record, :content_scope) || existing[:content_scope],
          source_id: fetch(record, :news_source_id) || existing[:source_id],
        }
      end
    end

    def load_payloads(contexts)
      article_ids = contexts.keys
      return [] if article_ids.empty?

      NewsArticle.includes(:news_source, :news_events, news_claims: { news_claim_actors: :news_actor })
        .where(id: article_ids)
        .filter_map do |article|
          claim = article.news_claims.find(&:primary?)
          context = contexts[article.id] || {}
          build_payload(article, claim, context)
        end
    end

    def build_payload(article, claim, context)
      return nil if article.content_scope == "out_of_scope"
      return nil if claim.blank?
      return nil if claim.event_family == "general"
      return nil unless CLUSTERABLE_EVENT_FAMILIES.include?(claim.event_family)
      return nil if GENERAL_EVENT_TYPES.include?(claim.event_type)

      event = article.news_events.max_by { |entry| entry.published_at || entry.fetched_at || entry.created_at }
      actors = claim.news_claim_actors.sort_by(&:position).filter_map do |claim_actor|
        actor = claim_actor.news_actor
        next unless actor

        {
          canonical_key: actor.canonical_key,
          name: actor.name,
          role: claim_actor.role,
          actor_type: actor.actor_type,
        }
      end

      title = context[:title] || article.title
      summary = context[:summary] || article.summary
      published_at = context[:published_at] || claim.published_at || article.published_at || event&.published_at
      fetched_at = context[:fetched_at] || article.fetched_at || event&.fetched_at
      location_name = scrub_location_name(context[:location_name] || event&.name)
      latitude = numeric_coordinate(context[:latitude] || event&.latitude)
      longitude = numeric_coordinate(context[:longitude] || event&.longitude)
      return nil if strict_location_event_type?(claim.event_type) && location_name.blank? && (latitude.nil? || longitude.nil?)

      {
        news_article_id: article.id,
        content_scope: context[:content_scope] || article.content_scope,
        source_id: context[:source_id] || article.news_source_id,
        source_kind: article.news_source&.source_kind,
        title: title,
        summary: summary,
        event_family: claim.event_family,
        event_type: claim.event_type,
        claim_confidence: claim.confidence.to_f,
        extraction_confidence: claim.extraction_confidence.to_f,
        actor_confidence: claim.actor_confidence.to_f,
        event_confidence: claim.event_confidence.to_f,
        source_reliability: claim.source_reliability.to_f,
        verification_status: claim.verification_status,
        geo_precision: claim.geo_precision,
        geo_confidence: claim.geo_confidence.to_f,
        claim_provenance: claim.provenance || {},
        published_at: published_at,
        fetched_at: fetched_at,
        location_name: location_name,
        latitude: latitude,
        longitude: longitude,
        actors: actors,
        text_tokens: normalized_tokens([ title, summary ].compact.join(" ")),
      }
    end

    def assign_payload(payload)
      cluster, score = best_cluster_for(payload)
      cluster ||= create_cluster_for(payload)
      score ||= 1.0

      {
        cluster: cluster,
        cluster_key: cluster.cluster_key,
        match_score: score.round(3),
        article_id: payload[:news_article_id],
      }
    end

    def best_cluster_for(payload)
      candidates = candidate_clusters(payload)
      best_cluster = nil
      best_score = nil

      candidates.each do |cluster|
        score = score_cluster(payload, cluster)
        next if score.nil?
        next if best_score && score <= best_score

        best_cluster = cluster
        best_score = score
      end

      return [ nil, nil ] if best_score.nil? || best_score < MATCH_THRESHOLD

      [ best_cluster, best_score ]
    end

    def candidate_clusters(payload)
      timestamp = payload[:published_at] || payload[:fetched_at] || Time.current
      window = clustering_window(payload[:event_family])

      NewsStoryCluster.where(event_family: payload[:event_family], content_scope: payload[:content_scope])
        .where("last_seen_at >= ?", timestamp - window)
        .order(last_seen_at: :desc)
        .limit(150)
    end

    def score_cluster(payload, cluster)
      return nil if cluster.event_family != payload[:event_family]

      timestamp = payload[:published_at] || payload[:fetched_at] || Time.current
      time_gap = (timestamp - cluster.last_seen_at).abs
      window = clustering_window(payload[:event_family])
      return nil if time_gap > window

      event_score = event_type_score(payload[:event_type], cluster.event_type)
      return nil if event_score.zero?

      actor_score = actor_overlap_score(payload, cluster)
      location_score = location_match_score(payload, cluster)
      text_score = text_similarity(payload[:text_tokens], Set.new(Array(cluster.metadata["text_tokens"])))
      time_score = 1.0 - [ time_gap / window.to_f, 1.0 ].min

      return nil if hard_veto?(payload, cluster, actor_score, location_score, text_score)

      (event_score * 0.25) +
        (actor_score * 0.25) +
        (location_score * 0.20) +
        (time_score * 0.15) +
        (text_score * 0.15)
    end

    def hard_veto?(payload, cluster, actor_score, location_score, text_score)
      return true if actor_score.zero? && location_score < 0.5 && text_score < 0.3

      payload_place = normalize_location_token(payload[:location_name])
      cluster_place = normalize_location_token(cluster.location_name)
      if payload_place.blank? && cluster_place.blank?
        return true if text_score < 0.4 && actor_score < 0.6
      end

      if strict_location_event_type?(payload[:event_type]) || strict_location_event_type?(cluster.event_type)
        return true if payload_place.blank? && cluster_place.blank? && text_score < 0.55
      end

      payload_lat = payload[:latitude]
      payload_lng = payload[:longitude]
      cluster_lat = cluster.latitude
      cluster_lng = cluster.longitude
      if payload_lat && payload_lng && cluster_lat && cluster_lng
        distance = haversine_km(payload_lat, payload_lng, cluster_lat, cluster_lng)
        return true if distance > (max_distance_km(payload[:event_family]) * 2.0)
      end

      false
    end

    def create_cluster_for(payload)
      timestamp = payload[:published_at] || payload[:fetched_at] || Time.current
      cluster_key = cluster_key_for(payload, timestamp)
      existing_cluster = NewsStoryCluster.find_by(cluster_key: cluster_key)
      return existing_cluster if existing_cluster

      attributes = cluster_attributes_for(payload, timestamp)

      NewsStoryCluster.create!(attributes.merge(cluster_key: cluster_key))
    rescue ActiveRecord::RecordNotUnique
      NewsStoryCluster.find_by!(cluster_key: cluster_key)
    end

    def cluster_key_for(payload, timestamp)
      actor_token = payload[:actors].map { |actor| actor[:canonical_key] }.sort.join("-")
      place_token = normalize_location_token(payload[:location_name])
      time_token = timestamp.utc.strftime("%Y%m%d%H")
      raw_key = [
        payload[:event_family],
        payload[:event_type],
        actor_token.presence,
        place_token.presence,
        time_token,
        payload[:news_article_id],
      ].compact.join("|")

      Digest::SHA1.hexdigest(raw_key)[0, 12]
    end

    def cluster_attributes_for(payload, timestamp)
      {
        canonical_title: payload[:title].to_s.scrub("")[0...500],
        content_scope: payload[:content_scope],
        event_family: payload[:event_family],
        event_type: payload[:event_type],
        location_name: payload[:location_name],
        latitude: payload[:latitude],
        longitude: payload[:longitude],
        geo_precision: geo_precision_for(payload),
        first_seen_at: timestamp,
        last_seen_at: timestamp,
        article_count: 0,
        source_count: 0,
        cluster_confidence: payload[:claim_confidence].presence || 0.5,
        source_reliability: payload[:source_reliability].to_f.round(3),
        geo_confidence: payload[:geo_confidence].to_f.round(3),
        verification_status: payload[:verification_status].presence || "single_source",
        metadata: {
          "actor_keys" => payload[:actors].map { |actor| actor[:canonical_key] },
          "actor_roles" => payload[:actors].map { |actor| { "key" => actor[:canonical_key], "role" => actor[:role], "name" => actor[:name] } },
          "text_tokens" => payload[:text_tokens].to_a,
        },
        provenance: {
          "lead_article_id" => payload[:news_article_id],
          "lead_source_id" => payload[:source_id],
          "source_ids" => Array(payload[:source_id]).compact,
          "article_ids" => [ payload[:news_article_id] ],
          "claim_provenance" => payload[:claim_provenance],
        },
      }
    end

    def apply_assignments(assignments)
      assignments.each_value do |assignment|
        persist_assignment(assignment)
      end
    end

    def persist_assignment(assignment)
      article_id = assignment[:article_id]
      cluster = assignment[:cluster]
      now = Time.current

      membership = NewsStoryMembership.find_or_initialize_by(news_article_id: article_id)
      previous_cluster = membership.persisted? ? membership.news_story_cluster : nil
      membership.update!(
        news_story_cluster: cluster,
        match_score: assignment[:match_score],
        primary: true,
        metadata: {
          "assigned_at" => now.iso8601,
        },
      )

      NewsEvent.where(news_article_id: article_id).update_all(
        story_cluster_id: cluster.cluster_key,
        updated_at: now
      )

      recalculate_cluster!(cluster)
      recalculate_cluster!(previous_cluster) if previous_cluster && previous_cluster.id != cluster.id
    end

    def clear_assignment(article_id)
      membership = NewsStoryMembership.find_by(news_article_id: article_id)
      previous_cluster = membership&.news_story_cluster
      membership&.destroy!
      NewsEvent.where(news_article_id: article_id).update_all(story_cluster_id: nil, updated_at: Time.current)
      recalculate_cluster!(previous_cluster) if previous_cluster
    end

    def recalculate_cluster!(cluster)
      return unless cluster

      memberships = cluster.news_story_memberships.includes(news_article: [ :news_source, :news_events, { news_claims: { news_claim_actors: :news_actor } } ]).to_a
      if memberships.empty?
        cluster.destroy!
        return
      end

      article_payloads = memberships.filter_map do |membership|
        article = membership.news_article
        claim = article.news_claims.find(&:primary?)
        build_payload(article, claim, {}).merge(match_score: membership.match_score)
      rescue NoMethodError
        nil
      end
      return if article_payloads.empty?

      lead_payload = article_payloads.max_by { |payload| lead_score(payload) }
      timestamps = article_payloads.map { |payload| payload[:published_at] || payload[:fetched_at] || Time.current }
      actor_roles = article_payloads.flat_map { |payload| payload[:actors] }
      actor_keys = actor_roles.map { |actor| actor[:canonical_key] }.uniq
      source_ids = article_payloads.filter_map { |payload| payload[:source_id] }.uniq
      coordinates = article_payloads.filter_map do |payload|
        lat = payload[:latitude]
        lng = payload[:longitude]
        next unless lat && lng

        [ lat, lng ]
      end
      latitude = coordinates.any? ? coordinates.sum(&:first) / coordinates.size.to_f : nil
      longitude = coordinates.any? ? coordinates.sum(&:last) / coordinates.size.to_f : nil
      location_name = predominant_location(article_payloads)
      avg_claim_confidence = article_payloads.sum { |payload| payload[:claim_confidence].to_f } / article_payloads.size.to_f
      avg_source_reliability = article_payloads.sum { |payload| payload[:source_reliability].to_f } / article_payloads.size.to_f
      avg_geo_confidence = article_payloads.sum { |payload| payload[:geo_confidence].to_f } / article_payloads.size.to_f
      avg_match_score = article_payloads.sum { |payload| payload[:match_score].to_f } / article_payloads.size.to_f
      source_factor = [ source_ids.size, 3 ].min / 3.0
      coverage_factor = [ article_payloads.size, 4 ].min / 4.0
      cluster_confidence = [
        (avg_claim_confidence * 0.45) + (avg_match_score * 0.25) + (avg_source_reliability * 0.15) + (avg_geo_confidence * 0.05) + (source_factor * 0.05) + (coverage_factor * 0.05),
        0.99,
      ].min.round(3)
      verification_status = if source_ids.size >= 2
        "multi_source"
      else
        lead_payload[:verification_status].presence || "single_source"
      end

      cluster.update!(
        canonical_title: lead_payload[:title].to_s.scrub("")[0...500],
        content_scope: lead_payload[:content_scope],
        event_family: predominant_value(article_payloads, :event_family) || lead_payload[:event_family],
        event_type: predominant_value(article_payloads, :event_type) || lead_payload[:event_type],
        location_name: location_name,
        latitude: latitude,
        longitude: longitude,
        geo_precision: predominant_value(article_payloads, :geo_precision) || (coordinates.any? ? "point" : (location_name.present? ? "named_area" : "unknown")),
        first_seen_at: timestamps.min,
        last_seen_at: timestamps.max,
        article_count: article_payloads.size,
        source_count: source_ids.size,
        cluster_confidence: cluster_confidence,
        source_reliability: avg_source_reliability.round(3),
        geo_confidence: avg_geo_confidence.round(3),
        verification_status: verification_status,
        lead_news_article_id: lead_payload[:news_article_id],
        metadata: {
          "actor_keys" => actor_keys,
          "actor_roles" => actor_roles.map { |actor| { "key" => actor[:canonical_key], "role" => actor[:role], "name" => actor[:name] } }.uniq,
          "actor_names" => actor_roles.map { |actor| actor[:name] }.uniq,
          "source_ids" => source_ids,
          "text_tokens" => article_payloads.flat_map { |payload| payload[:text_tokens].to_a }.uniq,
        },
        provenance: {
          "lead_article_id" => lead_payload[:news_article_id],
          "lead_source_id" => lead_payload[:source_id],
          "article_ids" => article_payloads.map { |payload| payload[:news_article_id] }.uniq,
          "source_ids" => source_ids,
          "source_kinds" => article_payloads.map { |payload| payload[:source_kind] }.compact.uniq,
          "claim_provenance" => article_payloads.map { |payload| payload[:claim_provenance] }.compact,
        },
      )
    end

    def lead_score(payload)
      score = payload[:claim_confidence].to_f
      score += 0.1 if payload[:summary].present?
      score += 0.1 if payload[:actors].any?
      score += 0.1 if payload[:source_kind] == "wire"
      score
    end

    def event_type_score(payload_event_type, cluster_event_type)
      return 1.0 if payload_event_type == cluster_event_type
      return 0.7 if compatible_event_types?(payload_event_type, cluster_event_type)

      0.0
    end

    def compatible_event_types?(left, right)
      COMPATIBLE_EVENT_GROUPS.any? { |group| group.include?(left) && group.include?(right) }
    end

    def strict_location_event_type?(event_type)
      STRICT_LOCATION_EVENT_TYPES.include?(event_type)
    end

    def actor_overlap_score(payload, cluster)
      payload_keys = payload[:actors].map { |actor| actor[:canonical_key] }.to_set
      cluster_keys = Set.new(Array(cluster.metadata["actor_keys"]))
      return 0.4 if payload_keys.empty? && cluster_keys.empty?
      return 0.2 if payload_keys.empty? || cluster_keys.empty?

      intersection = (payload_keys & cluster_keys).size.to_f
      union = (payload_keys | cluster_keys).size.to_f
      return 0.0 if intersection.zero?

      intersection / union
    end

    def location_match_score(payload, cluster)
      payload_lat = payload[:latitude]
      payload_lng = payload[:longitude]
      cluster_lat = cluster.latitude
      cluster_lng = cluster.longitude
      if payload_lat && payload_lng && cluster_lat && cluster_lng
        distance = haversine_km(payload_lat, payload_lng, cluster_lat, cluster_lng)
        max_distance = max_distance_km(payload[:event_family])
        return 1.0 if distance <= (max_distance * 0.2)
        return 0.8 if distance <= (max_distance * 0.5)
        return 0.55 if distance <= max_distance

        return 0.0
      end

      payload_place = normalize_location_token(payload[:location_name])
      cluster_place = normalize_location_token(cluster.location_name)
      return 0.85 if payload_place.present? && payload_place == cluster_place
      return 0.35 if payload_place.blank? || cluster_place.blank?

      0.0
    end

    def text_similarity(tokens_a, tokens_b)
      set_a = Set.new(tokens_a)
      set_b = Set.new(tokens_b)
      return 0.2 if set_a.empty? || set_b.empty?

      intersection = (set_a & set_b).size.to_f
      union = (set_a | set_b).size.to_f
      smaller = [ set_a.size, set_b.size ].min.to_f

      jaccard = intersection / union
      containment = intersection / smaller
      [ jaccard, containment ].max
    end

    def predominant_location(payloads)
      counts = payloads.each_with_object(Hash.new(0)) do |payload, mapping|
        key = payload[:location_name].presence
        next unless key

        mapping[key] += 1
      end
      return nil if counts.empty?

      counts.max_by { |_key, count| count }&.first
    end

    def predominant_value(payloads, key)
      counts = payloads.each_with_object(Hash.new(0)) do |payload, mapping|
        value = payload[key].presence
        next unless value

        mapping[value] += 1
      end
      return nil if counts.empty?

      counts.max_by { |_value, count| count }&.first
    end

    def geo_precision_for(payload)
      return "point" if payload[:latitude] && payload[:longitude]
      return "named_area" if payload[:location_name].present?

      "unknown"
    end

    def max_distance_km(event_family)
      FAMILY_MAX_DISTANCE_KM[event_family] || DEFAULT_MAX_DISTANCE_KM
    end

    def clustering_window(event_family)
      FAMILY_WINDOWS[event_family] || DEFAULT_WINDOW
    end

    def haversine_km(lat1, lng1, lat2, lng2)
      rad_per_deg = Math::PI / 180
      r_km = 6371.0
      dlat_rad = (lat2 - lat1) * rad_per_deg
      dlng_rad = (lng2 - lng1) * rad_per_deg
      lat1_rad = lat1 * rad_per_deg
      lat2_rad = lat2 * rad_per_deg

      a = Math.sin(dlat_rad / 2)**2 +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlng_rad / 2)**2
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      r_km * c
    end

    def normalized_tokens(text)
      text.to_s.downcase.scan(/[a-z0-9]{3,}/).reject do |token|
        %w[after against amid and are for from into near over says that the their these they this were with].include?(token)
      end.to_set
    end

    def normalize_location_token(value)
      value.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").squeeze(" ").strip.presence
    end

    def scrub_location_name(value)
      value.to_s.scrub("").strip.presence&.slice(0, 200)
    end

    def numeric_coordinate(value)
      return nil if value.blank?

      value.to_f
    end

    def normalize_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def fetch(record, key)
      record[key] || record[key.to_s]
    end
  end
end
