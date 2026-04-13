import { getDataSource } from "globe/utils"
import { situationClassLabel } from "globe/controller/detail_overlay/shared"

const BOUNDARY_URLS = {
  countries: [
    "/api/geography/boundaries?dataset=countries",
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson",
  ],
  admin1: [
    "/api/geography/boundaries?dataset=admin1",
  ],
}

const SURFACE_STYLES = {
  critical: { color: "#9b111e", alpha: 0.38, outline: 0.8 },
  high: { color: "#d32f2f", alpha: 0.3, outline: 0.7 },
  moderate: { color: "#f57c00", alpha: 0.24, outline: 0.62 },
  watch: { color: "#fbc02d", alpha: 0.16, outline: 0.5 },
}

export function applySituationSurfaceMethods(GlobeController) {
  GlobeController.prototype.toggleSituationSurfaces = function() {
    this.situationSurfacesVisible = this.hasSituationSurfacesToggleTarget && this.situationSurfacesToggleTarget.checked

    if (this.situationSurfacesVisible) {
      if (this._timelineActive) {
        this._stopSituationSurfaces({ clearData: true })
        this._toast("Situation surfaces are live-only in this experimental slice.")
      } else {
        this._startSituationSurfaces()
      }
    } else {
      this._stopSituationSurfaces({ clearData: true })
    }

    this._updateStats()
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._startSituationSurfaces = function() {
    if (this._situationSurfaceInterval) clearInterval(this._situationSurfaceInterval)
    if (!this.situationSurfacesVisible || this._timelineActive) return

    this._fetchSituationSurfaces()
    this._situationSurfaceInterval = setInterval(() => {
      if (this.situationSurfacesVisible && !this._timelineActive) this._fetchSituationSurfaces()
    }, 5 * 60 * 1000)
  }

  GlobeController.prototype._stopSituationSurfaces = function({ clearData = false } = {}) {
    if (this._situationSurfaceInterval) {
      clearInterval(this._situationSurfaceInterval)
      this._situationSurfaceInterval = null
    }

    this._situationSurfaceFetchToken += 1
    this._situationSurfaceRenderToken += 1
    this._clearSituationSurfaceEntities()

    if (clearData) {
      this._situationSurfaceData = []
      this._situationSurfaceSnapshotStatus = null
    }
  }

  GlobeController.prototype._fetchSituationSurfaces = async function() {
    if (!this.situationSurfacesVisible || this._timelineActive) return
    const fetchToken = ++this._situationSurfaceFetchToken

    try {
      const resp = await fetch("/api/situation_surfaces")
      if (fetchToken !== this._situationSurfaceFetchToken || !this.situationSurfacesVisible) return
      if (!resp.ok) return

      const data = await resp.json()
      if (fetchToken !== this._situationSurfaceFetchToken || !this.situationSurfacesVisible) return

      this._situationSurfaceData = data.surfaces || []
      this._situationSurfaceSnapshotStatus = data.snapshot_status || "ready"
      await this._renderSituationSurfaces()
      this._markFresh("situationSurfaces")
    } catch (error) {
      console.warn("Situation surface fetch failed:", error)
    }
  }

  GlobeController.prototype._renderSituationSurfaces = async function() {
    if (!this.situationSurfacesVisible) {
      this._clearSituationSurfaceEntities()
      return
    }

    const renderToken = ++this._situationSurfaceRenderToken
    const surfaces = this._situationSurfaceData || []
    const surfacesWithRings = []

    for (const surface of surfaces) {
      const rings = await this._surfaceRings(surface)
      if (renderToken !== this._situationSurfaceRenderToken || !this.situationSurfacesVisible) return
      if (rings.length > 0) surfacesWithRings.push({ surface, rings })
    }

    this._clearSituationSurfaceEntities()
    if (!surfacesWithRings.length) return

    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "situationSurfaces")

    ds.entities.suspendEvents()
    surfacesWithRings.forEach(({ surface, rings }, surfaceIdx) => {
      const style = surfaceStyle(surface)
      const color = Cesium.Color.fromCssColorString(style.color)
      const confidence = Math.max(0.2, Math.min(parseFloat(surface.confidence || 0.55), 1))
      const alpha = style.alpha * (0.65 + confidence * 0.35)
      const key = this._situationSurfaceEntityKey(surface.id || `surface-${surfaceIdx}`)
      const center = centroidForRings(rings)
      if (center) {
        if (surface.lat == null) surface.lat = center.lat
        if (surface.lng == null) surface.lng = center.lng
        surface.center_lat = center.lat
        surface.center_lng = center.lng
      }

      rings.forEach((ring, ringIdx) => {
        const positions = ring
          .filter(coord => Array.isArray(coord) && coord.length >= 2)
          .map(coord => Cesium.Cartesian3.fromDegrees(coord[1], coord[0]))
        if (positions.length < 3) return

        const entity = ds.entities.add({
          id: `surface-poly-${key}-${ringIdx}`,
          polygon: {
            hierarchy: new Cesium.PolygonHierarchy(positions),
            material: color.withAlpha(alpha),
            outline: true,
            outlineColor: color.withAlpha(style.outline),
            outlineWidth: surface.scope === "local" ? 1.5 : 2.5,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
            zIndex: 2000 + surfaceIdx * 10 + ringIdx,
          },
          properties: {
            surfaceId: surface.id || "",
            label: surface.label || "",
            severity: surface.severity_tier || "",
            scope: surface.scope || "",
          },
        })
        this._situationSurfaceEntities.push(entity)
      })

      if (shouldLabelSurface(surface)) {
        if (center) {
          const label = ds.entities.add({
            id: `surface-label-${key}`,
            position: Cesium.Cartesian3.fromDegrees(center.lng, center.lat, 9000),
            label: {
              text: surfaceLabel(surface),
              font: "bold 11px 'JetBrains Mono', monospace",
              fillColor: color.withAlpha(0.98),
              outlineColor: Cesium.Color.BLACK,
              outlineWidth: 4,
              style: Cesium.LabelStyle.FILL_AND_OUTLINE,
              verticalOrigin: Cesium.VerticalOrigin.CENTER,
              horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
              disableDepthTestDistance: Number.POSITIVE_INFINITY,
              scaleByDistance: new Cesium.NearFarScalar(4e5, 1.0, 7e6, 0.55),
              translucencyByDistance: new Cesium.NearFarScalar(4e5, 1.0, 1.2e7, 0.0),
            },
          })
          this._situationSurfaceEntities.push(label)
        }
      }
    })
    ds.entities.resumeEvents()

    this._requestRender()
  }

  GlobeController.prototype._clearSituationSurfaceEntities = function() {
    const ds = this._ds["situationSurfaces"]
    if (ds && this._situationSurfaceEntities?.length) {
      ds.entities.suspendEvents()
      this._situationSurfaceEntities.forEach(entity => ds.entities.remove(entity))
      ds.entities.resumeEvents()
    }
    this._situationSurfaceEntities = []
    this._requestRender()
  }

  GlobeController.prototype._situationSurfaceEntityKey = function(value) {
    return encodeURIComponent(String(value ?? "unknown"))
  }

  GlobeController.prototype._situationSurfaceByEntityKey = function(encodedKey) {
    const key = decodeURIComponent(encodedKey)
    return (this._situationSurfaceData || []).find(surface => `${surface.id}` === key)
  }

  GlobeController.prototype.showSituationSurfaceDetail = function(surface, options = {}) {
    if (!surface) return
    if (this._showCompactEntityDetail?.("situation_surface", surface, options)) return

    const style = SURFACE_STYLES[surface.severity_tier] || SURFACE_STYLES.watch
    const evidence = (surface.evidence || []).slice(0, 4).map(item => {
      const title = this._escapeHtml(item.title || "Supporting evidence")
      const source = item.source ? `<div style="font:400 9px var(--gt-mono);color:#666;margin-top:2px;">${this._escapeHtml(item.source)}</div>` : ""
      if (item.url) {
        return `<a href="${this._safeUrl(item.url)}" target="_blank" rel="noopener" style="display:block;text-decoration:none;padding:5px 0;border-bottom:1px solid rgba(255,255,255,0.06);">
          <div style="font:400 11px var(--gt-mono);color:#e8edf5;line-height:1.35;">${title}</div>${source}
        </a>`
      }
      return `<div style="padding:5px 0;border-bottom:1px solid rgba(255,255,255,0.06);font:400 11px var(--gt-mono);color:#e8edf5;line-height:1.35;">${title}${source}</div>`
    }).join("")

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${style.color};">
        <i class="fa-solid fa-draw-polygon" style="margin-right:6px;"></i>${this._escapeHtml(surface.label || "Situation surface")}
      </div>
      <div style="display:inline-flex;gap:6px;align-items:center;padding:2px 8px;border-radius:3px;background:${style.color};color:#06080d;font:800 10px var(--gt-mono);letter-spacing:1px;margin-bottom:8px;">
        ${(surface.severity_tier || "watch").toUpperCase()} · ${this._escapeHtml(surface.scope || "local")}
      </div>
      <div class="detail-grid">
        <div class="detail-field"><span class="detail-label">Class</span><span class="detail-value">${this._escapeHtml(situationClassLabel(surface.situation_class))}</span></div>
        <div class="detail-field"><span class="detail-label">Graph</span><span class="detail-value">${surface.ontology?.graph_link_count || 0} links</span></div>
        <div class="detail-field"><span class="detail-label">Sources</span><span class="detail-value">${surface.source_count || 0}</span></div>
        <div class="detail-field"><span class="detail-label">Confidence</span><span class="detail-value">${Math.round((surface.confidence || 0) * 100)}%</span></div>
      </div>
      <div style="font:400 11px var(--gt-sans,sans-serif);color:rgba(220,230,245,0.76);line-height:1.45;margin:8px 0 10px;">
        ${this._escapeHtml(surface.evidence_summary || "Derived from current live signals.")}
      </div>
      ${evidence ? `<div style="margin-top:10px;"><div style="font:700 9px var(--gt-mono);color:#8b95a6;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">Evidence</div>${evidence}</div>` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype._surfaceRings = async function(surface) {
    const boundaryRings = await this._boundaryRings(surface?.boundary_ref)
    if (boundaryRings.length > 0) return boundaryRings

    return normalizeRings(surface?.geometry?.rings)
  }

  GlobeController.prototype._boundaryRings = async function(boundaryRef) {
    if (!boundaryRef) return []
    const features = await this._loadSituationSurfaceBoundaryFeatures(boundaryRef.dataset || "countries")
    if (!features.length) return []

    const feature = features.find(candidate => boundaryFeatureMatches(candidate, boundaryRef))
    if (!feature) return []

    return boundaryFeatureRings(feature)
  }

  GlobeController.prototype._loadSituationSurfaceBoundaryFeatures = async function(dataset) {
    const key = BOUNDARY_URLS[dataset] ? dataset : "countries"
    this._situationSurfaceBoundaryFeatures ||= {}
    this._situationSurfaceBoundaryFetches ||= {}

    if (this._situationSurfaceBoundaryFeatures[key]?.length) return this._situationSurfaceBoundaryFeatures[key]
    if (this._situationSurfaceBoundaryFetches[key]) return this._situationSurfaceBoundaryFetches[key]

    this._situationSurfaceBoundaryFetches[key] = (async () => {
      for (const url of BOUNDARY_URLS[key]) {
        try {
          const response = await fetch(url, url.startsWith("/") ? { credentials: "same-origin" } : undefined)
          if (!response.ok) continue
          const geojson = await response.json()
          if (geojson?.type === "FeatureCollection" && Array.isArray(geojson.features)) {
            this._situationSurfaceBoundaryFeatures[key] = geojson.features
            return this._situationSurfaceBoundaryFeatures[key]
          }
        } catch (error) {
          console.warn(`Situation surface boundary fetch failed for ${url}:`, error)
        }
      }
      this._situationSurfaceBoundaryFeatures[key] = []
      return []
    })()

    return this._situationSurfaceBoundaryFetches[key]
  }
}

function normalizeRings(rings) {
  return (Array.isArray(rings) ? rings : []).map(ring => {
    return (Array.isArray(ring) ? ring : []).filter(coord => Array.isArray(coord) && coord.length >= 2)
  }).filter(ring => ring.length >= 3)
}

function boundaryFeatureMatches(feature, ref) {
  const props = feature?.properties || {}
  const names = [
    props.NAME, props.ADMIN, props.NAME_LONG, props.BRK_NAME, props.SOVEREIGNT,
    props.name, props.name_en, props.name_alt, props.woe_name, props.gn_name,
  ].filter(Boolean).flatMap(value => `${value}`.split("|")).map(value => value.trim().toLowerCase())
  const codes = [
    props.ISO_A2, props.ISO_A3, props.ADM0_A3, props.GU_A3,
    props.iso_a2, props.adm0_a3, props.iso_3166_2, props.adm1_code, props.code_hasc,
  ].filter(Boolean).map(value => `${value}`.toUpperCase())
  const admins = [
    props.ADMIN, props.admin, props.geonunit, props.SOVEREIGNT,
  ].filter(Boolean).map(value => `${value}`.toLowerCase())

  const refName = `${ref.name || ""}`.toLowerCase()
  const refCode = `${ref.iso_a2 || ref.iso_a3 || ref.iso_3166_2 || ref.adm1_code || ""}`.toUpperCase()
  const refAdmin = `${ref.admin || ref.country || ""}`.toLowerCase()
  const adminMatches = !refAdmin || admins.includes(refAdmin)

  if ((ref.dataset || "countries") === "admin1") {
    return (refCode && codes.includes(refCode)) || (refName && adminMatches && names.includes(refName))
  }

  return (refName && names.some(name => `${name}`.toLowerCase() === refName)) ||
    (refCode && codes.includes(refCode))
}

function boundaryFeatureRings(feature) {
  const geom = feature?.geometry
  if (!geom) return []

  const polygons = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []
  return polygons.map(poly => {
    const exterior = Array.isArray(poly) ? poly[0] : null
    return (Array.isArray(exterior) ? exterior : []).filter(coord => Array.isArray(coord) && coord.length >= 2).map(coord => [coord[1], coord[0]])
  }).filter(ring => ring.length >= 3)
}

function centroidForRings(rings) {
  const points = rings.flat()
  if (!points.length) return null
  const lat = points.reduce((sum, coord) => sum + coord[0], 0) / points.length
  const lng = points.reduce((sum, coord) => sum + coord[1], 0) / points.length
  return { lat, lng }
}

function shouldLabelSurface(surface) {
  return surface.severity_tier === "critical" ||
    surface.severity_tier === "high" ||
    surface.scope === "corridor" ||
    surface.attention_score >= 80
}

function surfaceLabel(surface) {
  return `${situationClassLabel(surface.situation_class).toUpperCase()} · ${surface.label || "Surface"}`
}

function surfaceStyle(surface) {
  if (surface?.situation_class === "strategic_chokepoint" && surface?.severity_tier === "high") {
    return { color: "#f57c00", alpha: 0.26, outline: 0.72 }
  }

  return SURFACE_STYLES[surface?.severity_tier] || SURFACE_STYLES.watch
}
