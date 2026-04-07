module Api
  class InternetOutagesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      recent_events = time_scoped(InternetOutage).order(started_at: :desc).limit(100)
      outages = parse_time_range ? [] : InternetOutageRefreshService.cached_summary
      outages = derive_summary_from_events(recent_events) if outages.blank?

      render json: {
        summary: outages.sort_by { |o| -(o[:score] || 0) }.first(50),
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

    def derive_summary_from_events(events)
      level_rank = {
        "minor" => 1,
        "moderate" => 2,
        "major" => 3,
        "severe" => 4,
        "critical" => 5,
      }

      events
        .group_by(&:entity_code)
        .filter_map do |code, rows|
          next if code.blank?

          strongest = rows.max_by { |event| [event.score.to_f, level_rank.fetch(event.level.to_s, 0), event.started_at.to_i] }
          next unless strongest

          {
            code: code,
            name: strongest.entity_name,
            score: rows.map { |event| event.score.to_f }.max.round(1),
            eventCount: rows.size,
            level: rows.max_by { |event| level_rank.fetch(event.level.to_s, 0) }&.level || strongest.level,
          }
        end
    end
  end
end
