export function applyConnectionsMethods(GlobeController) {

  // Fetch connections for an entity and render into the detail panel
  GlobeController.prototype._fetchConnections = async function(entityType, lat, lng, metadata = {}) {
    const container = document.getElementById("detail-connections")
    if (!container) return

    container.innerHTML = `<div style="font:400 10px monospace;color:#888;padding:4px 0;">Checking connections...</div>`

    try {
      const params = new URLSearchParams({ entity_type: entityType, lat, lng })
      Object.entries(metadata).forEach(([k, v]) => {
        if (v != null && v !== "") params.append(`metadata[${k}]`, v)
      })

      const resp = await fetch(`/api/connections?${params}`)
      if (!resp.ok) { container.innerHTML = ""; return }

      const data = await resp.json()
      const verified = data.verified || []
      const nearby = data.nearby || []

      if (verified.length === 0 && nearby.length === 0) {
        container.innerHTML = ""
        return
      }

      let html = ""

      if (verified.length > 0) {
        html += `<div style="margin-top:10px;border-top:1px solid #333;padding-top:8px;">
          <div style="font:600 9px monospace;color:#4fc3f7;letter-spacing:1px;text-transform:uppercase;margin-bottom:6px;">CONNECTIONS</div>`
        verified.forEach(c => { html += this._renderConnectionCard(c) })
        html += `</div>`
      }

      if (nearby.length > 0) {
        html += `<div style="margin-top:8px;${verified.length === 0 ? "border-top:1px solid #333;padding-top:8px;" : ""}">
          <div style="font:600 9px monospace;color:#888;letter-spacing:1px;text-transform:uppercase;margin-bottom:6px;">NEARBY</div>`
        nearby.forEach(c => { html += this._renderConnectionCard(c, true) })
        html += `</div>`
      }

      container.innerHTML = html
    } catch (e) {
      console.warn("Connections fetch failed:", e)
      container.innerHTML = ""
    }
  }

  GlobeController.prototype._renderConnectionCard = function(conn, dimmed = false) {
    const opacity = dimmed ? "0.7" : "1"
    const items = conn.items || []
    let itemsHtml = ""
    if (items.length > 0) {
      itemsHtml = `<div style="margin-top:3px;">`
      items.forEach(item => {
        const label = item.name || item.callsign || item.title || ""
        const sub = item.fuel ? `${item.fuel} ${item.capacity ? item.capacity.toLocaleString() + " MW" : ""}` :
                    item.deaths != null ? `${item.deaths} deaths` :
                    item.magnitude ? `M${item.magnitude}` : ""
        itemsHtml += `<div style="font:400 9px monospace;color:#aaa;padding:1px 0;">· ${label}${sub ? " — " + sub : ""}</div>`
      })
      itemsHtml += `</div>`
    }

    return `<div style="opacity:${opacity};padding:5px 7px;margin-bottom:4px;background:rgba(255,255,255,0.03);border:1px solid ${conn.color || "#555"}33;border-left:3px solid ${conn.color || "#555"};border-radius:4px;">
      <div style="display:flex;align-items:center;gap:5px;">
        <i class="fa-solid ${conn.icon || "fa-link"}" style="color:${conn.color || "#888"};font-size:11px;"></i>
        <span style="font:600 11px monospace;color:${conn.color || "#ccc"};">${conn.title || ""}</span>
      </div>
      ${conn.detail ? `<div style="font:400 10px monospace;color:#aaa;margin-top:2px;">${conn.detail}</div>` : ""}
      ${itemsHtml}
    </div>`
  }

  // Helper: HTML placeholder to insert into detail panels
  GlobeController.prototype._connectionsPlaceholder = function() {
    return `<div id="detail-connections"></div>`
  }
}
