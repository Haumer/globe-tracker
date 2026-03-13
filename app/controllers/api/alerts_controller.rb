module Api
  class AlertsController < ApplicationController
    before_action :authenticate_user!

    def index
      WatchEvaluator.evaluate(current_user)
      alerts = current_user.alerts.unseen.recent
      unseen_count = alerts.count

      render json: {
        unseen_count: unseen_count,
        alerts: alerts.map { |a| alert_json(a) }
      }
    end

    def update
      alert = current_user.alerts.find(params[:id])
      alert.update!(seen: true)
      # Reset cooldown so the watch won't immediately re-fire
      alert.watch&.update_column(:last_triggered_at, Time.current)
      head :no_content
    end

    def mark_all_seen
      # Reset cooldowns on all watches that generated unseen alerts
      watch_ids = current_user.alerts.unseen.where.not(watch_id: nil).distinct.pluck(:watch_id)
      current_user.watches.where(id: watch_ids).update_all(last_triggered_at: Time.current)
      current_user.alerts.unseen.update_all(seen: true)
      head :no_content
    end

    private

    def alert_json(a)
      {
        id: a.id,
        watch_id: a.watch_id,
        title: a.title,
        details: a.details,
        entity_type: a.entity_type,
        entity_id: a.entity_id,
        lat: a.lat,
        lng: a.lng,
        seen: a.seen,
        created_at: a.created_at.iso8601,
      }
    end
  end
end
