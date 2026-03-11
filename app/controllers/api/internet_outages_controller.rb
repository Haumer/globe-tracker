module Api
  class InternetOutagesController < ApplicationController
    include TimelineRecorder
    skip_before_action :authenticate_user!

    IODA_BASE = "https://api.ioda.inetintel.cc.gatech.edu/v2"

    def index
      require "net/http"
      require "json"

      now = Time.current
      outages = []

      # Skip external API fetch when querying historical data (timeline mode)
      unless params[:from].present? && params[:to].present?
        from_ts = 24.hours.ago.to_i
        until_ts = now.to_i

        events_data = fetch_ioda("#{IODA_BASE}/outages/events?entityType=country&from=#{from_ts}&until=#{until_ts}&limit=200&format=ioda")
        summary_data = fetch_ioda("#{IODA_BASE}/outages/summary?entityType=country&from=#{from_ts}&until=#{until_ts}")

        # Persist events
        if events_data.is_a?(Array)
          records = events_data.filter_map do |ev|
            entity = ev["entity"] || {}
            next if entity["code"].blank?

            {
              external_id: "#{entity['code']}-#{ev['datasource']}-#{ev['from']}",
              entity_type: entity["type"] || "country",
              entity_code: entity["code"],
              entity_name: entity["name"],
              datasource: ev["datasource"],
              score: ev["score"]&.to_f,
              level: outage_level(ev["score"]&.to_f || 0),
              condition: ev["method"],
              started_at: ev["from"] ? Time.at(ev["from"]) : nil,
              ended_at: ev["until"] ? Time.at(ev["until"]) : nil,
              fetched_at: now,
              created_at: now,
              updated_at: now,
            }
          end

          InternetOutage.insert_all(records) if records.any?

          # Record to timeline — outages have no lat/lng (country-level)
          inserted = InternetOutage.where(external_id: records.map { |r| r[:external_id] })
          tl_rows = inserted.map do |io|
            {
              event_type: "internet_outage",
              eventable_type: "InternetOutage",
              eventable_id: io.id,
              latitude: nil,
              longitude: nil,
              recorded_at: io.started_at || Time.current,
              created_at: Time.current,
              updated_at: Time.current,
            }
          end
          TimelineEvent.upsert_all(tl_rows, unique_by: [:eventable_type, :eventable_id]) if tl_rows.any?
        end

        # Build summary for map from live data
        if summary_data.is_a?(Array)
          outages = summary_data.filter_map do |s|
            entity = s["entity"] || {}
            scores = s["scores"] || {}
            overall = scores["overall"]&.to_f || 0
            event_cnt = s["event_cnt"]&.to_i || 0

            next if event_cnt < 1

            {
              code: entity["code"],
              name: entity["name"],
              score: overall.round(1),
              eventCount: event_cnt,
              level: outage_level(overall),
            }
          end
        end
      end

      recent_events = if params[:from].present? && params[:to].present?
                        from = Time.parse(params[:from]) rescue 24.hours.ago
                        to = Time.parse(params[:to]) rescue Time.current
                        InternetOutage.in_range(from, to)
                      else
                        InternetOutage.recent
                      end.order(started_at: :desc).limit(100)
      render json: {
        summary: outages.sort_by { |o| -o[:score] }.first(50),
        events: recent_events.map { |ev|
          {
            id: ev.external_id,
            code: ev.entity_code,
            name: ev.entity_name,
            datasource: ev.datasource,
            score: ev.score,
            level: ev.level,
            from: ev.started_at&.to_i,
            until: ev.ended_at&.to_i,
          }
        },
      }
    end

    private

    def fetch_ioda(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      response = http.request(Net::HTTP::Get.new(uri))

      return nil unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body)
      parsed["data"]
    rescue StandardError => e
      Rails.logger.error("IODA fetch error: #{e.message}")
      nil
    end

    def outage_level(score)
      if score >= 100_000 then "critical"
      elsif score >= 10_000 then "severe"
      elsif score >= 1_000 then "moderate"
      else "minor"
      end
    end
  end
end
