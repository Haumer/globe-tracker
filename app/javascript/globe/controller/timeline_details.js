export function applyTimelineDetailMethods(GlobeController) {
  GlobeController.prototype._showTimelineFlightDetail = function(icao, snap) {
    const extra = snap.x || {}
    const isMil = extra.mil || extra.military
    const color = isMil ? "#ef5350" : "#c8d2e1"
    const time = snap.seenAt ? `${new Date(snap.seenAt).toUTCString().slice(17, 25)} UTC` : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid ${isMil ? "fa-jet-fighter" : "fa-plane"}" style="margin-right:6px;"></i>${this._escapeHtml(snap.callsign || icao)}
        <span style="font:400 9px var(--gt-mono);color:#888;margin-left:6px;">PLAYBACK</span>
      </div>
      <div class="detail-country">${this._escapeHtml(icao)} ${isMil ? "· MILITARY" : ""}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Altitude</span>
          <span class="detail-value">${snap.alt ? `${Math.round(snap.alt)} ft` : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Speed</span>
          <span class="detail-value">${snap.spd ? `${Math.round(snap.spd)} kts` : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Heading</span>
          <span class="detail-value">${snap.hdg ? `${Math.round(snap.hdg)}°` : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Position</span>
          <span class="detail-value" style="font-size:10px;">${snap.lat?.toFixed(3)}, ${snap.lng?.toFixed(3)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Snapshot</span>
          <span class="detail-value" style="font-size:10px;">${time}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">On Ground</span>
          <span class="detail-value">${snap.gnd ? "Yes" : "No"}</span>
        </div>
      </div>
      ${extra.sq ? `<div style="margin-top:6px;font:400 10px var(--gt-mono);color:#ffc107;">Squawk: ${extra.sq}</div>` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype._showTimelineShipDetail = function(mmsi, snap) {
    const extra = snap.x || {}
    const time = snap.seenAt ? `${new Date(snap.seenAt).toUTCString().slice(17, 25)} UTC` : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#26c6da;">
        <i class="fa-solid fa-ship" style="margin-right:6px;"></i>${this._escapeHtml(snap.callsign || mmsi)}
        <span style="font:400 9px var(--gt-mono);color:#888;margin-left:6px;">PLAYBACK</span>
      </div>
      <div class="detail-country">MMSI: ${this._escapeHtml(mmsi)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Speed</span>
          <span class="detail-value">${snap.spd ? `${snap.spd.toFixed(1)} kts` : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Heading</span>
          <span class="detail-value">${snap.hdg ? `${Math.round(snap.hdg)}°` : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Position</span>
          <span class="detail-value" style="font-size:10px;">${snap.lat?.toFixed(3)}, ${snap.lng?.toFixed(3)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Snapshot</span>
          <span class="detail-value" style="font-size:10px;">${time}</span>
        </div>
      </div>
      ${extra.destination ? `<div style="margin-top:6px;font:400 10px var(--gt-mono);color:#aaa;">Destination: ${extra.destination}</div>` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }
}
