module Api
  class NewsController < ApplicationController
    include TimelineRecorder
    skip_before_action :authenticate_user!

    INTERESTING_THEMES = %w[
      ARMEDCONFLICT PROTEST TERROR ECON_BANKRUPTCY ECON_STOCKMARKET
      ENV_EARTHQUAKE ENV_VOLCANO ENV_FLOOD ENV_HURRICANE ENV_WILDFIRE
      HEALTH_PANDEMIC HEALTH_EPIDEMIC CYBER_ATTACK LEADER
      DISPLACEMENT REFUGEE FAMINE ASSASSINATION ARREST
      MILITARY REBELLION COUP CEASEFIRE PEACE
      GENERAL_HEALTH MEDICAL EPU_CATS_NATIONAL_SECURITY
      WB_695_POVERTY CRISIS
    ].freeze

    def index
      require "net/http"
      require "json"

      # Skip external API fetch when querying historical data (timeline mode)
      unless params[:from].present? && params[:to].present?
        uri = URI("https://api.gdeltproject.org/api/v1/gkg_geojson")
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          body = response.body.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          data = JSON.parse(body)
          features = data["features"] || []
          now = Time.current

          seen_urls = Set.new
          records = []

          features.each do |f|
            coords = f.dig("geometry", "coordinates")
            props = f["properties"] || {}
            url = props["url"]

            next if coords.nil? || coords.length < 2
            next if url.blank? || seen_urls.include?(url)
            seen_urls.add(url)

            lng, lat = coords[0].to_f, coords[1].to_f
            next if lat == 0.0 && lng == 0.0

            themes_raw = (props["mentionedthemes"] || "").split(";").map(&:strip).reject(&:blank?).uniq
            matched_themes = themes_raw.select { |t| INTERESTING_THEMES.any? { |it| t.include?(it) } }
            next if matched_themes.empty?

            tone = props["urltone"]&.to_f || 0.0
            level = tone_level(tone)
            category = categorize(matched_themes)
            published = begin
                          props["urlpubtimedate"].present? ? Time.parse(props["urlpubtimedate"]) : nil
                        rescue
                          nil
                        end

            records << {
              url: url,
              name: props["name"],
              latitude: lat,
              longitude: lng,
              tone: tone.round(1),
              level: level,
              category: category,
              themes: matched_themes.first(5).to_json,
              published_at: published,
              fetched_at: now,
              created_at: now,
              updated_at: now,
            }
          end

          # Scrub any remaining invalid UTF-8 from individual fields
          records.each do |r|
            r.each { |k, v| r[k] = v.scrub("") if v.is_a?(String) }
          end

          if records.any?
            begin
              NewsEvent.upsert_all(records, unique_by: :url)
              record_timeline_events(
                event_type: "news",
                model_class: NewsEvent,
                unique_key: :url,
                unique_values: records.map { |r| r[:url] },
                time_column: :published_at
              )
            rescue => e
              Rails.logger.error("NewsController upsert error: #{e.message}")
            end
          end
        end
      end

      # Return news — support timeline filtering
      events = if params[:from].present? && params[:to].present?
                 from = Time.parse(params[:from]) rescue 24.hours.ago
                 to = Time.parse(params[:to]) rescue Time.current
                 NewsEvent.in_range(from, to)
               else
                 NewsEvent.recent
               end.order(Arel.sql("ABS(tone) DESC")).limit(500)
      render json: events.map { |ev|
        themes = ev.themes.is_a?(String) ? JSON.parse(ev.themes) : (ev.themes || [])
        {
          lat: ev.latitude,
          lng: ev.longitude,
          name: ev.name,
          url: ev.url,
          tone: ev.tone,
          level: ev.level,
          category: ev.category,
          themes: themes,
          time: ev.published_at&.iso8601,
        }
      }
    end

    private

    def tone_level(tone)
      if tone <= -5 then "critical"
      elsif tone <= -2 then "negative"
      elsif tone <= 2 then "neutral"
      else "positive"
      end
    end

    def categorize(themes)
      if themes.any? { |t| t.include?("ARMEDCONFLICT") || t.include?("MILITARY") || t.include?("TERROR") }
        "conflict"
      elsif themes.any? { |t| t.include?("PROTEST") || t.include?("REBELLION") || t.include?("COUP") }
        "unrest"
      elsif themes.any? { |t| t.include?("ENV_") || t.include?("EARTHQUAKE") || t.include?("VOLCANO") || t.include?("FLOOD") || t.include?("WILDFIRE") || t.include?("HURRICANE") }
        "disaster"
      elsif themes.any? { |t| t.include?("HEALTH") || t.include?("PANDEMIC") || t.include?("EPIDEMIC") || t.include?("MEDICAL") }
        "health"
      elsif themes.any? { |t| t.include?("ECON_") || t.include?("POVERTY") || t.include?("FAMINE") }
        "economy"
      elsif themes.any? { |t| t.include?("PEACE") || t.include?("CEASEFIRE") }
        "diplomacy"
      else
        "other"
      end
    end
  end
end
