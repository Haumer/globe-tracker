class EventsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "global_events"
  end

  # Broadcast a breaking event to all connected clients
  def self.broadcast_event(event_type, data)
    ActionCable.server.broadcast("global_events", {
      type: event_type,
      data: data,
      timestamp: Time.current.iso8601,
    })
  end

  # Convenience methods for common event types
  def self.earthquake(quake)
    broadcast_event("earthquake", {
      id: quake.external_id,
      title: quake.title,
      mag: quake.magnitude,
      lat: quake.latitude,
      lng: quake.longitude,
      depth: quake.depth,
      time: quake.event_time&.to_i&.*(1000),
    })
  end

  def self.conflict_escalation(zone)
    broadcast_event("conflict_escalation", {
      cell_key: zone[:cell_key],
      situation: zone[:situation_name],
      theater: zone[:theater],
      pulse_score: zone[:pulse_score],
      trend: zone[:escalation_trend],
      lat: zone[:lat],
      lng: zone[:lng],
      headline: zone[:top_headlines]&.first,
    })
  end

  def self.gps_jamming(snapshot)
    broadcast_event("gps_jamming", {
      lat: snapshot.cell_lat,
      lng: snapshot.cell_lng,
      pct: snapshot.percentage,
      level: snapshot.level,
    })
  end
end
