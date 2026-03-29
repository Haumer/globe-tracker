export function applyNewsFeedMethods(GlobeController) {
  GlobeController.prototype.closeNewsFeed = function() {
    this._setNewsDotOpacity(1.0)
    if (this._syncRightPanels) this._syncRightPanels()
  }

  GlobeController.prototype.switchNewsTab = function(event) {
    const tab = event.currentTarget.dataset.tab
    this._newsActiveTab = tab

    const tabs = event.currentTarget.parentElement.children
    for (const t of tabs) t.classList.toggle("nf-tab--active", t.dataset.tab === tab)

    if (this.hasNewsArticlesPaneTarget) this.newsArticlesPaneTarget.style.display = tab === "articles" ? "" : "none"
    if (this.hasNewsFlowsPaneTarget) this.newsFlowsPaneTarget.style.display = tab === "flows" ? "" : "none"

    if (tab === "articles") {
      this._renderNewsArticleList()
      this._setNewsDotOpacity(0.25)
    } else {
      this._setNewsDotOpacity(1.0)
      this._renderRegionFlows()
    }
  }

  GlobeController.prototype.filterNewsArticles = function() {
    this._renderNewsArticleList()
  }

  GlobeController.prototype.toggleNewsCatChip = function(event) {
    event.currentTarget.classList.toggle("active")
    this._renderNewsArticleList()
  }

  GlobeController.prototype._getReadNewsSet = function() {
    try {
      const raw = localStorage.getItem("gt_read_news")
      return raw ? new Set(JSON.parse(raw)) : new Set()
    } catch {
      return new Set()
    }
  }

  GlobeController.prototype._markNewsRead = function(url) {
    if (!url) return
    const readSet = this._getReadNewsSet()
    readSet.add(url)
    const arr = [...readSet]
    if (arr.length > 500) arr.splice(0, arr.length - 500)
    try { localStorage.setItem("gt_read_news", JSON.stringify(arr)) } catch {}
  }

  GlobeController.prototype._renderNewsArticleList = function() {
    if (!this.hasNewsArticleListTarget) return
    const events = this._newsData || []

    const activeChips = []
    if (this.hasNewsCatChipsTarget) {
      this.newsCatChipsTarget.querySelectorAll(".nf-cat-chip.active").forEach(btn => {
        activeChips.push(btn.dataset.category)
      })
    }

    const search = this.hasNewsArticleSearchTarget ? this.newsArticleSearchTarget.value.toLowerCase().trim() : ""
    const sortBy = this.hasNewsSortSelectTarget ? this.newsSortSelectTarget.value : "newest"
    const hideRead = this.hasNewsHideReadToggleTarget ? this.newsHideReadToggleTarget.checked : false
    const readSet = this._getReadNewsSet()

    const categoryColors = {
      conflict: "#f44336", unrest: "#ff9800", disaster: "#ff5722",
      health: "#4caf50", economy: "#2196f3", diplomacy: "#9c27b0", cyber: "#00bcd4", other: "#90a4ae",
    }

    const filtered = events
      .map((ev, i) => ({ ...ev, _idx: i }))
      .filter(ev => {
        const actorSearch = (ev.actors || []).map(actor => actor.name || "").join(" ").toLowerCase()
        if (activeChips.length > 0 && !activeChips.includes(ev.category)) return false
        if (search && !(ev.title || "").toLowerCase().includes(search) &&
            !(ev.name || "").toLowerCase().includes(search) &&
            !(ev.publisher || ev.source || "").toLowerCase().includes(search) &&
            !actorSearch.includes(search)) return false
        if (hideRead && readSet.has(ev.url)) return false
        return true
      })
      .sort((a, b) => {
        if (sortBy === "priority") {
          return (b.priority || 0) - (a.priority || 0)
        } else if (sortBy === "intensity") {
          return Math.abs(b.tone || 0) - Math.abs(a.tone || 0)
        }
        if (a.time && b.time) return b.time.localeCompare(a.time)
        if (a.time) return -1
        if (b.time) return 1
        return 0
      })

    if (this.hasNewsFeedCountTarget) {
      this.newsFeedCountTarget.textContent = `${filtered.length} article${filtered.length !== 1 ? "s" : ""}`
    }

    if (filtered.length === 0) {
      this.newsArticleListTarget.innerHTML = '<div style="padding:24px 14px;text-align:center;color:var(--gt-text-dim);font:500 11px var(--gt-mono);">No articles match filters</div>'
      return
    }

    const html = filtered.map(ev => {
      const color = categoryColors[ev.category] || "#90a4ae"
      let domain = ev.publisher || ev.source || ""
      if (!domain && ev.url) {
        try { domain = new URL(ev.url).hostname.replace(/^www\./, "") } catch {}
      }

      const timeAgo = ev.time ? this._timeAgo(new Date(ev.time)) : ""
      const tone = ev.tone || 0
      const actorNames = (ev.actors || []).map(actor => actor.name).filter(Boolean)
      let toneBg, toneColor, toneLabel
      if (tone <= -2) { toneBg = "rgba(244,67,54,0.12)"; toneColor = "#ef5350"; toneLabel = "negative" }
      else if (tone >= 2) { toneBg = "rgba(76,175,80,0.12)"; toneColor = "#66bb6a"; toneLabel = "positive" }
      else { toneBg = "rgba(144,164,174,0.1)"; toneColor = "#90a4ae"; toneLabel = "neutral" }

      const title = this._escapeHtml(ev.title || ev.name || "Untitled")
      const isRead = readSet.has(ev.url)
      const readClass = isRead ? " nf-card--read" : ""
      let clusterBadge = ""
      if (ev.source_count && ev.source_count > 1) {
        const sourceNames = (ev.sources || []).filter(s => s && s !== "").map(s => this._escapeHtml(s)).join(", ")
        clusterBadge = `<span class="nf-card-cluster" title="${sourceNames}">${ev.source_count} sources · ${sourceNames}</span>`
      }

      return `<div class="nf-card${readClass}" data-action="click->globe#focusNewsArticle" data-news-idx="${ev._idx}" data-news-url="${this._escapeHtml(ev.url || "")}"
        <div class="nf-card-bar" style="background:${color};"></div>
        <div class="nf-card-body">
          <div class="nf-card-headline">${title}${clusterBadge}</div>
          <div class="nf-card-meta">
            <span class="nf-card-source">${this._escapeHtml(domain)}</span>
            ${timeAgo ? `<span class="nf-card-dot">&middot;</span><span class="nf-card-time">${timeAgo}</span>` : ""}
            ${actorNames.length ? `<span class="nf-card-dot">&middot;</span><span class="nf-card-time">${this._escapeHtml(actorNames.slice(0, 2).join(", "))}</span>` : ""}
          </div>
          <div class="nf-card-footer">
            ${ev.threat && ev.threat !== "info" ? `<span class="nf-card-tone" style="background:${{critical:"rgba(244,67,54,0.2)",high:"rgba(255,87,34,0.15)",medium:"rgba(255,152,0,0.12)",low:"rgba(102,187,106,0.1)"}[ev.threat]};color:${{critical:"#f44336",high:"#ff5722",medium:"#ff9800",low:"#66bb6a"}[ev.threat]}">${ev.threat}</span>` : ""}
            <span class="nf-card-tone" style="background:${toneBg};color:${toneColor}">${toneLabel}</span>
            <a href="${this._safeUrl(ev.url)}" target="_blank" rel="noopener" class="nf-card-link" onclick="event.stopPropagation();this.closest('.nf-card').classList.add('nf-card--read')" title="Open article"><i class="fa-solid fa-arrow-up-right-from-square"></i></a>
            <button class="nf-card-locate" data-action="click->globe#locateNewsArticle" data-news-idx="${ev._idx}" title="Locate on map"><i class="fa-solid fa-location-crosshairs"></i></button>
          </div>
        </div>
      </div>`
    }).join("")

    this.newsArticleListTarget.innerHTML = html
    this._fetchTrending()
  }

  GlobeController.prototype._fetchTrending = async function() {
    if (!this.hasNewsTrendingBarTarget) return
    const bar = this.newsTrendingBarTarget

    const now = Date.now()
    if (this._lastTrendingFetch && now - this._lastTrendingFetch < 120000) return
    this._lastTrendingFetch = now

    bar.innerHTML = '<span class="nf-trending-label">TRENDING</span><span class="nf-trend-chip nf-trend-chip--mild">Loading trends...</span>'

    try {
      const resp = await fetch("/api/trending")
      if (!resp.ok) { bar.innerHTML = ""; return }
      const trends = await resp.json()
      if (!trends || trends.length === 0) { bar.innerHTML = ""; return }

      bar.innerHTML = '<span class="nf-trending-label">TRENDING</span>' +
        trends.slice(0, 10).map(t => {
          const heat = t.velocity > 5 ? "nf-trend-chip--hot" : t.velocity > 2 ? "nf-trend-chip--warm" : "nf-trend-chip--mild"
          return `<span class="nf-trend-chip ${heat}" data-action="click->globe#filterNewsByKeyword" data-keyword="${t.keyword}">${t.keyword} <span class="nf-trend-count">&times;${t.recent}</span></span>`
        }).join("")
    } catch {
      bar.innerHTML = ""
    }
  }

  GlobeController.prototype.filterNewsByKeyword = function(event) {
    const keyword = event.currentTarget.dataset.keyword
    if (this.hasNewsArticleSearchTarget) {
      this.newsArticleSearchTarget.value = keyword
      this._renderNewsArticleList()
    }
  }

  GlobeController.prototype.focusNewsArticle = function(event) {
    const idx = parseInt(event.currentTarget.dataset.newsIdx)
    const ev = this._newsData?.[idx]
    if (!ev) return
    this._markNewsRead(ev.url)
    const card = event.currentTarget
    if (card) card.classList.add("nf-card--read")
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 2000000),
      duration: 1.0,
    })
    if (this._buildNewsContext && this._setSelectedContext) {
      this._setSelectedContext(this._buildNewsContext(ev))
    }
    const entity = this._newsEntities?.[idx]
    if (entity?.point) {
      const origSize = entity.point.pixelSize?.getValue() || 10
      entity.point.pixelSize = origSize * 2.5
      entity.point.outlineWidth = 6
      setTimeout(() => {
        if (entity.point) {
          entity.point.pixelSize = origSize
          entity.point.outlineWidth = 3
        }
      }, 2000)
    }
  }

  GlobeController.prototype.locateNewsArticle = function(event) {
    event.stopPropagation()
    const idx = parseInt(event.currentTarget.dataset.newsIdx)
    const ev = this._newsData?.[idx]
    if (!ev) return
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 2000000),
      duration: 1.0,
    })
  }

  GlobeController.prototype.focusNewsArc = function(event) {
    const idx = parseInt(event.currentTarget.dataset.arcIdx)
    const arc = this._newsArcData?.[idx]
    if (!arc) return
    const midLat = (arc.srcLat + arc.evtLat) / 2
    const midLng = (arc.srcLng + arc.evtLng) / 2
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(midLng, midLat, 5000000),
      duration: 1.0,
    })
    this.showNewsArcDetail(idx)
  }

  GlobeController.prototype.showNewsArcDetail = function(arcIdx) {
    const arc = this._newsArcData?.[arcIdx]
    if (!arc) return

    const categoryColors = {
      conflict: "#f44336", unrest: "#ff9800", disaster: "#ff5722",
      health: "#e91e63", economy: "#ffc107", diplomacy: "#4caf50", cyber: "#7c4dff", other: "#90a4ae",
    }

    const articleList = arc.articles.map(a => {
      const color = categoryColors[a.category] || "#90a4ae"
      const toneColor = a.tone < -2 ? "#f44336" : a.tone > 2 ? "#4caf50" : "#90a4ae"
      return `<div style="padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <div style="font:500 10px var(--gt-mono);color:${color};">
          <a href="${this._safeUrl(a.url)}" target="_blank" rel="noopener" style="color:${color};text-decoration:none;">${this._escapeHtml(a.domain)}</a>
        </div>
        <div style="font:400 9px var(--gt-mono);color:var(--gt-text-dim);line-height:1.3;">${this._escapeHtml(a.name || "")}</div>
        <div style="font:400 9px var(--gt-mono);color:${toneColor};">${a.category} · tone ${a.tone}</div>
      </div>`
    }).join("")

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#ffab40;">
        <i class="fa-solid fa-newspaper" style="margin-right:6px;"></i>Media Attention
      </div>
      <div class="detail-country">${this._escapeHtml(arc.srcCity)} → ${this._escapeHtml(arc.evtName)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Articles</span>
          <span class="detail-value" style="color:#ffab40;">${arc.count}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Source</span>
          <span class="detail-value">${this._escapeHtml(arc.srcCity)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">About</span>
          <span class="detail-value">${this._escapeHtml(arc.evtName)}</span>
        </div>
      </div>
      <div style="margin-top:8px;font:600 9px var(--gt-mono);color:#ffab40;letter-spacing:1px;text-transform:uppercase;">Publishers</div>
      ${articleList}
    `
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype.showNewsDetail = function(ev) {
    const locKey = `${ev.lat.toFixed(0)},${ev.lng.toFixed(0)}`
    this._showClusterArcs(locKey)
    if (this._buildNewsContext && this._setSelectedContext) {
      this._setSelectedContext(this._buildNewsContext(ev))
    }

    const categoryColors = {
      conflict: "#f44336", unrest: "#ff9800", disaster: "#ff5722",
      health: "#e91e63", economy: "#ffc107", diplomacy: "#4caf50", cyber: "#7c4dff", other: "#90a4ae",
    }
    const categoryIcons = {
      conflict: "fa-crosshairs", unrest: "fa-bullhorn", disaster: "fa-hurricane",
      health: "fa-heart-pulse", economy: "fa-chart-line", diplomacy: "fa-handshake", cyber: "fa-shield-halved", other: "fa-newspaper",
    }
    const color = categoryColors[ev.category] || "#90a4ae"
    const icon = categoryIcons[ev.category] || "fa-newspaper"

    const nearby = (this._newsData || []).filter(n =>
      n.url !== ev.url &&
      Math.abs(n.lat - ev.lat) < 1.0 &&
      Math.abs(n.lng - ev.lng) < 1.0
    )

    const cleanThemes = (ev.themes || [])
      .map(t => t.replace(/^.*_/, "").replace(/([a-z])([A-Z])/g, "$1 $2"))
      .filter(t => t.length > 2 && t.length < 25 && !/^[A-Z]{3,}$/.test(t))
    const themeTags = cleanThemes.map(t =>
      `<span style="display:inline-block;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.12);padding:2px 7px;border-radius:3px;margin:2px;font-size:10px;color:rgba(200,210,225,0.7);">${t.toLowerCase()}</span>`
    ).join("")

    const timeStr = ev.time ? this._timeAgo(new Date(ev.time)) : ""
    const actorSummary = (ev.actors || []).map(actor => {
      const role = actor.role ? ` (${actor.role.replace(/_/g, " ")})` : ""
      return `${actor.name || ""}${role}`
    }).filter(Boolean)
    const claimType = ev.claim_event_type ? ev.claim_event_type.replace(/_/g, " ") : ""
    const locationParts = (ev.name || "").split(",").map(s => s.trim())
    const dedupedLocation = [...new Set(locationParts)].join(", ")
    const sourceName = (ev.publisher || ev.source || "").replace(/^GN:\s*/, "")

    const sentimentLabel = Math.abs(ev.tone) >= 7 ? "Strongly negative" :
      Math.abs(ev.tone) >= 4 ? "Negative" :
      Math.abs(ev.tone) >= 2 ? "Moderately negative" : "Neutral"

    const nearbyHtml = nearby.length > 0 ? `
      <div style="margin-top:12px;padding-top:10px;border-top:1px solid rgba(255,255,255,0.08);">
        <div style="font-size:10px;text-transform:uppercase;letter-spacing:1px;color:rgba(200,210,225,0.5);margin-bottom:8px;">
          ${nearby.length} nearby stor${nearby.length === 1 ? "y" : "ies"}
        </div>
        ${nearby.slice(0, 10).map(n => {
          const nColor = categoryColors[n.category] || "#90a4ae"
          const nTitle = n.title || n.name || "Untitled"
          const nSource = (n.publisher || n.source || n.name || "").replace(/^GN:\s*/, "").split(",")[0]
          const nTime = n.time ? this._timeAgo(new Date(n.time)) : ""
          return `<a href="${this._safeUrl(n.url)}" target="_blank" rel="noopener" style="display:block;padding:6px 0;color:rgba(200,210,225,0.85);text-decoration:none;font-size:11px;line-height:1.35;border-bottom:1px solid rgba(255,255,255,0.04);">
            <span style="color:${nColor};margin-right:4px;">●</span>
            ${this._escapeHtml(nTitle.length > 80 ? nTitle.substring(0, 78) + "…" : nTitle)}
            <div style="color:rgba(200,210,225,0.4);font-size:9px;margin-top:2px;margin-left:12px;">${this._escapeHtml(nSource)}${nTime ? " · " + nTime : ""}</div>
          </a>`
        }).join("")}
      </div>
    ` : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid ${icon}" style="margin-right:6px;"></i>${this._escapeHtml(ev.title || ev.category.charAt(0).toUpperCase() + ev.category.slice(1))}
      </div>
      <div class="detail-country">${this._escapeHtml(dedupedLocation || "Unknown location")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Coverage</span>
          <span class="detail-value">${sentimentLabel}</span>
        </div>
        ${timeStr ? `<div class="detail-field">
          <span class="detail-label">Published</span>
          <span class="detail-value">${timeStr}</span>
        </div>` : ""}
        ${sourceName ? `<div class="detail-field">
          <span class="detail-label">Source</span>
          <span class="detail-value">${this._escapeHtml(sourceName)}</span>
        </div>` : ""}
        ${claimType ? `<div class="detail-field">
          <span class="detail-label">Claim</span>
          <span class="detail-value">${this._escapeHtml(claimType)}</span>
        </div>` : ""}
        ${actorSummary.length ? `<div class="detail-field">
          <span class="detail-label">Actors</span>
          <span class="detail-value">${this._escapeHtml(actorSummary.join(", "))}</span>
        </div>` : ""}
        ${ev.credibility ? `<div class="detail-field">
          <span class="detail-label">Credibility</span>
          <span class="detail-value">${this._formatCredibility(ev.credibility)}</span>
        </div>` : ""}
      </div>
      ${themeTags ? `<div style="margin:8px 0;">${themeTags}</div>` : ""}
      <a href="${this._safeUrl(ev.url)}" target="_blank" rel="noopener" class="detail-track-btn">Read Article →</a>
      ${nearbyHtml}
    `
    this.detailPanelTarget.style.display = ""

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 300000),
      duration: 1.5,
    })
  }

  GlobeController.prototype._formatCredibility = function(cred) {
    if (!cred) return ""
    const parts = cred.split("/")
    const tier = parts[0] || ""
    const risk = parts[1] || ""
    const affiliation = parts[2] || ""
    const tierLabel = { tier1: "Wire/Gov", tier2: "Major", tier3: "Specialty", tier4: "Aggregator" }[tier] || tier
    const riskColor = { low: "#66bb6a", medium: "#ff9800", high: "#f44336" }[risk] || "#90a4ae"
    let html = `<span style="color:${riskColor};">${tierLabel}</span>`
    if (affiliation) html += ` <span style="color:#90a4ae;font-size:9px;">(${affiliation})</span>`
    return html
  }
}
