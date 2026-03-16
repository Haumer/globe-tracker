class AlertsChannel < ApplicationCable::Channel
  def subscribed
    if current_user
      stream_for current_user
    else
      reject
    end
  end

  def unsubscribed
    # Clean up
  end

  # Broadcast a new alert to a specific user
  def self.notify(user, alert)
    broadcast_to(user, {
      type: "new_alert",
      alert: {
        id: alert.id,
        title: alert.title,
        entity_type: alert.entity_type,
        entity_id: alert.entity_id,
        lat: alert.lat,
        lng: alert.lng,
        details: alert.details,
        watch_name: alert.watch&.name,
        created_at: alert.created_at.iso8601,
      },
    })
  end

  # Broadcast unseen count update
  def self.update_badge(user)
    count = user.alerts.unseen.count
    broadcast_to(user, {
      type: "badge_update",
      unseen_count: count,
    })
  end
end
