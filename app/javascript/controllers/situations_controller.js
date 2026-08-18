import { Controller } from "@hotwired/stimulus"
import { COUNTRY_CENTROIDS } from "globe/country_centroids"

// The situations globe. Deliberately its own Cesium instance rather than a
// layer inside globe_controller: the point of the view is that nothing else is
// on the map, and the layer registry, quick bar and preference sync all exist
// to put other things on it.
//
// The shape drawn is a convergence, never an area. Reports collapse inward onto
// an anchor, exposure fans back outward from it. Every coordinate rendered is
// one somebody measured -- the only derived position is the medoid anchor for
// actor-keyed situations, and it is drawn hollow so it never reads as a place
// the story owns.

const EVIDENCE_COLOR = "#4fc3f7"   // inbound: reports that make the claim
const EXPOSURE_COLOR = "#ffb300"   // outbound: countries the claim reaches
const ASSET_COLOR = "#ff7043"      // ring 1: assets beside the anchor
const REGISTRY_COLOR = "#ffc44d"
const MEDOID_COLOR = "#8fa3b8"

// Arc apex as a fraction of ground distance, capped so a Washington-to-Hormuz
// arc does not leave the atmosphere.
const ARC_PEAK_RATIO = 0.22
const ARC_PEAK_MAX_M = 1_400_000
const ARC_SEGMENTS = 48

// A facility is a point, not an area. Registry anchors without a measured
// radius get this nominal footprint so they are visible on approach, and the
// panel says it is nominal rather than surveyed.
const NOMINAL_FACILITY_RADIUS_M = 6_000

// Below this on-screen diameter a ground footprint is a smudge, so the anchor
// falls back to the fixed-size symbol. Above it, the footprint is the anchor
// and scales with the globe like anything else on the surface.
const FOOTPRINT_MIN_PX = 26
const LOCATOR_RADIUS_PX = 3.5

export default class extends Controller {
  static targets = ["list", "panel", "status"]
  static values = { cesiumToken: String }

  connect() {
    this._situations = []
    this._selectedId = null
    this._loadCesium().then(() => this._boot()).catch((error) => {
      console.error("Cesium failed to load", error)
      this._setStatus("Globe failed to load")
    })
  }

  disconnect() {
    try { this.viewer?.destroy() } catch {}
    this.viewer = null
  }

  // ── boot ────────────────────────────────────────────────────────────

  _loadCesium() {
    if (window.Cesium) return Promise.resolve()

    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = "https://cesium.com/downloads/cesiumjs/releases/1.124/Build/Cesium/Widgets/widgets.css"
    document.head.appendChild(link)

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = "https://cesium.com/downloads/cesiumjs/releases/1.124/Build/Cesium/Cesium.js"
      script.onload = resolve
      script.onerror = () => reject(new Error("Cesium script failed"))
      document.head.appendChild(script)
    })
  }

  async _boot() {
    const Cesium = window.Cesium
    if (this.cesiumTokenValue) Cesium.Ion.defaultAccessToken = this.cesiumTokenValue

    // Same dark ArcGIS basemap the main globe uses, for the same reason: it
    // keeps Ion quota out of the picture and the anchors readable.
    const baseLayer = Cesium.ImageryLayer.fromProviderAsync(
      Cesium.ArcGisMapServerImageryProvider.fromUrl(
        "https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer"
      )
    )

    this.viewer = new Cesium.Viewer("situations-viewer", {
      baseLayerPicker: false,
      baseLayer: baseLayer,
      geocoder: false,
      homeButton: false,
      navigationHelpButton: false,
      sceneModePicker: false,
      timeline: false,
      animation: false,
      fullscreenButton: false,
      vrButton: false,
      infoBox: false,
      selectionIndicator: false,
      creditContainer: document.createElement("div"),
      requestRenderMode: true,
      maximumRenderTimeChange: Infinity,
    })

    const scene = this.viewer.scene
    scene.globe.enableLighting = false
    scene.skyAtmosphere.show = true
    scene.globe.showGroundAtmosphere = true
    scene.backgroundColor = Cesium.Color.BLACK
    scene.globe.baseColor = Cesium.Color.fromCssColorString("#0a0c10")

    this._anchors = new Cesium.CustomDataSource("situation-anchors")
    this._detail = new Cesium.CustomDataSource("situation-detail")
    await this.viewer.dataSources.add(this._anchors)
    await this.viewer.dataSources.add(this._detail)

    this.viewer.camera.setView({
      destination: Cesium.Cartesian3.fromDegrees(35, 20, 22_000_000)
    })

    this._wirePicking()
    await this._fetch()
  }

  async _fetch() {
    try {
      const resp = await fetch("/api/situations")
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
      const data = await resp.json()
      this._situations = data.situations || []
      this._windowDays = data.window_days
      this._renderAnchors()
      this._renderList()
      this._setStatus(this._summary())
    } catch (error) {
      console.error("Situations fetch failed", error)
      this._setStatus("Could not load situations")
    }
  }

  _summary() {
    const total = this._situations.length
    const anchored = this._situations.filter((s) => s.anchor.kind === "registry").length
    const stories = this._situations.reduce((sum, s) => sum + s.member_count, 0)
    const articles = this._situations.reduce((sum, s) => sum + s.article_count, 0)
    return `${total} situations · ${stories} stories · ${articles} reports · ${anchored} anchored on a registry entity · ${this._windowDays}d`
  }

  // ── anchors ─────────────────────────────────────────────────────────

  _renderAnchors() {
    const Cesium = window.Cesium
    this._anchors.entities.removeAll()

    // Anchors cluster hard -- JAZAN, Najran and Bab el-Mandeb sit within a few
    // hundred km of each other -- and Cesium will happily stack their labels.
    // Alternating the label above and below the glyph separates the common case
    // without a layout pass.
    let labelled = 0

    this._situations.forEach((situation) => {
      const { lat, lng } = situation.anchor
      if (lat == null || lng == null) return

      const registry = situation.anchor.kind === "registry"
      const below = registry && labelled++ % 2 === 1
      const footprint = this._footprint(situation)
      const swap = footprint.radius_m ? this._swapDistance(footprint.radius_m) : null
      // A footprint anchor now shows a small locator, so the label sits close to
      // it rather than clearing a disc that is no longer drawn.
      const offset = swap ? 16 : this._glyphRadius(situation) + 10

      this._anchors.entities.add({
        id: `sit-${situation.id}`,
        position: Cesium.Cartesian3.fromDegrees(lng, lat),
        // A measured extent is drawn on the globe at every distance, so it lies
        // on the sphere and foreshortens toward the limb the way the ground it
        // covers does. It used to hand off to a screen-space disc past the point
        // where it fell below FOOTPRINT_MIN_PX, which meant that from any
        // overview only the anchor you had flown to was a real footprint and the
        // other seventeen were flat discs pasted at constant pixel size — the
        // same shape, on the same globe, meaning something else.
        ellipse: swap && {
          semiMajorAxis: footprint.radius_m,
          semiMinorAxis: footprint.radius_m,
          material: Cesium.Color.fromCssColorString(REGISTRY_COLOR).withAlpha(0.22),
          outline: true,
          outlineColor: Cesium.Color.fromCssColorString("#fff6e0").withAlpha(0.85),
          outlineWidth: 2,
          // Explicit height rather than CLAMP_TO_GROUND: this viewer has no
          // terrain provider, and clamped geometry silently drops its outline —
          // which is the whole registry/medoid distinction.
          height: 0,
        },
        // The symbol is now a locator rather than a second footprint. Past the
        // swap distance the ground circle is smaller than a few pixels and needs
        // something findable, but a disc scaled by report count sitting where a
        // footprint would sit is the confusion above; this one is fixed and
        // small. An anchor with no extent has nothing else to draw, so it keeps
        // the full symbol at every distance.
        billboard: {
          image: swap ? this._locatorGlyph(situation) : this._medoidGlyph(),
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          distanceDisplayCondition: swap
            ? new Cesium.DistanceDisplayCondition(swap, Number.MAX_VALUE)
            : undefined,
        },
        label: {
          text: situation.name,
          font: `600 12px "JetBrains Mono", monospace`,
          fillColor: Cesium.Color.fromCssColorString(registry ? "#ffe0a3" : "#c8d4e0"),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: below ? Cesium.VerticalOrigin.TOP : Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, below ? offset : -offset),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        situationId: situation.id,
      })
    })

    this._applyAnchorStyling()
  }

  // Cesium does not declutter labels, and eleven actor-keyed situations pile
  // into the Middle East. Registry anchors keep their name because their
  // position is a real claim; a medoid's is not, so it earns a label only on
  // hover or selection. The left rail is the readable index either way.
  _applyAnchorStyling() {
    const Cesium = window.Cesium
    const selected = this._selectedId

    this._anchors.entities.values.forEach((entity) => {
      const situation = this._situations.find((s) => s.id === entity.situationId)
      if (!situation) return

      const registry = situation.anchor.kind === "registry"
      const isSelected = situation.id === selected
      const isHovered = situation.id === this._hoveredId

      const dimmed = selected != null && !isSelected
      entity.billboard.color = Cesium.Color.WHITE.withAlpha(dimmed ? 0.25 : 1)

      // Only anchors with a measurable extent carry a footprint.
      if (entity.ellipse) {
        entity.ellipse.material = Cesium.Color.fromCssColorString(REGISTRY_COLOR)
          .withAlpha(dimmed ? 0.07 : 0.22)
        entity.ellipse.outlineColor = Cesium.Color.fromCssColorString("#fff6e0")
          .withAlpha(dimmed ? 0.25 : 0.85)
      }

      entity.label.show = selected != null
        ? isSelected
        : registry || isHovered
    })

    this.viewer.scene.requestRender()
  }

  // Both symbols are fixed. Nothing drawn on this globe is sized by report
  // count any more: a screen-space disc that grows with coverage sits in the
  // same place, and reads as the same kind of shape, as a footprint that grows
  // with the thing it covers. Volume belongs in the rail, where it is a number
  // and a sparkline rather than an area.
  _glyphRadius() {
    return LOCATOR_RADIUS_PX
  }

  // What a circle drawn on the ground is allowed to mean: the extent of the
  // thing named, and nothing else.
  //
  //   corridor  → its own surveyed radius_km
  //   facility  → a nominal footprint, declared as nominal
  //   medoid    → none. An actor has no extent, and the two candidates for one
  //               are both lies of a different kind: report volume would assert
  //               an area nobody measured, and median report spread inverts the
  //               whole view -- Houthis measures 1,067 km, so the anchors we
  //               trust least would draw the largest shapes on the globe. They
  //               stay fixed-size symbols at every zoom. The scatter is already
  //               visible on selection, as the arcs themselves.
  _footprint(situation) {
    if (situation.anchor.kind !== "registry") {
      return { radius_m: null, basis: "none", label: "none — an actor has no extent" }
    }

    // A corridor's radius is surveyed and an occurrence's is derived from its
    // magnitude, so the wording names the thing rather than assuming a corridor
    // — the Colombia quake draws 202.8 km and is not a strait.
    const km = situation.concerns?.radius_km
    if (km) {
      const kind = situation.concerns?.entity_type === "place" ? "measured extent" : "corridor radius"
      return { radius_m: km * 1000, basis: "measured", label: `${km} km ${kind}` }
    }

    return {
      radius_m: NOMINAL_FACILITY_RADIUS_M,
      basis: "nominal",
      label: `${NOMINAL_FACILITY_RADIUS_M / 1000} km nominal facility footprint`
    }
  }

  // Camera distance at which the footprint shrinks to FOOTPRINT_MIN_PX. Nearer
  // than this the footprint is the anchor and scales with the globe; further,
  // the fixed-size symbol takes over. The handover is exclusive, so there is no
  // range where both draw and none where neither does.
  _swapDistance(radiusMeters) {
    const height = this.viewer.scene.canvas.clientHeight || 800
    const fov = this.viewer.camera.frustum.fovy || Math.PI / 3
    const focalPx = (height / 2) / Math.tan(fov / 2)
    return (2 * radiusMeters * focalPx) / FOOTPRINT_MIN_PX
  }

  // Marks where a footprint is when the footprint itself is too small to find.
  // Deliberately not sized by anything: the only circle on this globe whose size
  // carries a measurement is the one drawn on the ground.
  _locatorGlyph(situation) {
    const exposed = situation.rings.ring3_countries.total > 0
    const radius = LOCATOR_RADIUS_PX
    const size = 18
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = size
    const ctx = canvas.getContext("2d")
    const c = size / 2

    ctx.beginPath()
    ctx.arc(c, c, radius, 0, Math.PI * 2)
    ctx.fillStyle = REGISTRY_COLOR
    ctx.fill()
    ctx.lineWidth = 1.5
    ctx.strokeStyle = "#fff6e0"
    ctx.stroke()

    if (exposed) {
      ctx.beginPath()
      ctx.arc(c, c, radius + 3.5, 0, Math.PI * 2)
      ctx.lineWidth = 1.5
      ctx.strokeStyle = EXPOSURE_COLOR
      ctx.globalAlpha = 0.7
      ctx.stroke()
    }

    return canvas
  }

  // The anchor with no extent, and the reason it gets no circle on the ground.
  //
  // A ground circle needs a radius, and the only measurable candidate is the
  // spread of the member reports around the medoid -- which measures the
  // geocoder rather than the story. The Houthi members sit on 17 distinct points
  // for 53 reports, 72% of them on three: Sanaa, Washington and Riyadh. So its
  // half-radius of 1,067km is the Sanaa-to-Riyadh gap and its 75th percentile of
  // 10,204km is Washington. Hamas puts 21 of 42 on Gaza and one on Sydney.
  // Drawing any of that on the ground would assert an area nobody measured.
  //
  // Canvas rather than a Cesium point, because the registry/medoid distinction
  // is the whole honesty claim of the view and a point primitive cannot draw a
  // dashed ring.
  _medoidGlyph() {
    const radius = LOCATOR_RADIUS_PX
    const size = 18
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = size
    const ctx = canvas.getContext("2d")
    const c = size / 2

    // Dashed and cool-toned so it never reads as a located thing, and the same
    // size as the registry locator so neither kind of anchor claims more of the
    // globe than the other. Faintly filled because eleven of eighteen situations
    // are anchored this way and a bare 1.5px dash disappears into the basemap --
    // light, though: a dark disc reads as a hole punched in the globe.
    ctx.beginPath()
    ctx.arc(c, c, radius + 2, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(143, 163, 184, 0.28)"
    ctx.fill()
    ctx.setLineDash([3, 2])
    ctx.lineWidth = 1.5
    ctx.strokeStyle = MEDOID_COLOR
    ctx.stroke()
    ctx.setLineDash([])

    ctx.beginPath()
    ctx.arc(c, c, 1.75, 0, Math.PI * 2)
    ctx.fillStyle = MEDOID_COLOR
    ctx.fill()

    return canvas
  }

  // ── selection ───────────────────────────────────────────────────────

  _wirePicking() {
    const Cesium = window.Cesium
    const handler = new Cesium.ScreenSpaceEventHandler(this.viewer.scene.canvas)

    handler.setInputAction((click) => {
      const picked = this.viewer.scene.pick(click.position)
      const id = picked?.id?.situationId
      if (id) this.select(id)
      else this._clearSelection()
    }, Cesium.ScreenSpaceEventType.LEFT_CLICK)

    handler.setInputAction((movement) => {
      const picked = this.viewer.scene.pick(movement.endPosition)
      const id = picked?.id?.situationId ?? null
      if (id === this._hoveredId) return

      this._hoveredId = id
      this.viewer.scene.canvas.style.cursor = id ? "pointer" : "default"
      this._applyAnchorStyling()
    }, Cesium.ScreenSpaceEventType.MOUSE_MOVE)

    this._handler = handler
  }

  selectFromList(event) {
    this.select(Number(event.currentTarget.dataset.situationId))
  }

  select(id) {
    const situation = this._situations.find((s) => s.id === id)
    if (!situation) return

    this._selectedId = id
    this._drawDetail(situation)
    this._renderPanel(situation)
    this._renderList()
    this._applyAnchorStyling()
    this._flyTo(situation)
  }

  _clearSelection() {
    this._selectedId = null
    this._detail.entities.removeAll()
    this.panelTarget.style.display = "none"
    this._renderList()
    this._applyAnchorStyling()
  }

  close() {
    this._clearSelection()
  }

  // ── the drawing that matters ────────────────────────────────────────

  _drawDetail(situation) {
    const Cesium = window.Cesium
    this._detail.entities.removeAll()

    const anchor = situation.anchor
    const newest = situation.last_seen_at ? Date.parse(situation.last_seen_at) : Date.now()
    const oldest = situation.first_seen_at ? Date.parse(situation.first_seen_at) : newest
    const span = Math.max(newest - oldest, 1)

    // Inbound: every report that makes this one story, converging on the anchor.
    situation.members.forEach((member, index) => {
      if (member.lat == null || member.lng == null) return

      const age = member.last_seen_at ? (newest - Date.parse(member.last_seen_at)) / span : 1
      const alpha = 0.25 + 0.55 * (1 - Math.min(age, 1))
      const positions = this._arcPositions(member, anchor)
      if (!positions) return

      this._detail.entities.add({
        id: `sit-arc-${situation.id}-${index}`,
        polyline: {
          positions: positions,
          width: 1.2,
          material: Cesium.Color.fromCssColorString(EVIDENCE_COLOR).withAlpha(alpha),
          arcType: Cesium.ArcType.NONE,
        },
        memberIndex: index,
        situationId: situation.id,
      })

      this._detail.entities.add({
        id: `sit-report-${situation.id}-${index}`,
        position: Cesium.Cartesian3.fromDegrees(member.lng, member.lat),
        point: {
          pixelSize: 4,
          color: Cesium.Color.fromCssColorString(EVIDENCE_COLOR).withAlpha(alpha + 0.15),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        memberIndex: index,
        situationId: situation.id,
      })
    })

    // Outbound ring 1: assets sitting beside the anchor.
    //
    // situationId on every detail entity, not just the anchors. Picking reads
    // it and treats its absence as "nothing was picked", so an untagged dot in
    // front of the selected situation closed the panel the moment you clicked
    // the thing the panel was describing.
    situation.rings.ring1_assets.shown.forEach((asset, index) => {
      if (asset.lat == null || asset.lng == null) return

      this._detail.entities.add({
        id: `sit-asset-${situation.id}-${index}`,
        position: Cesium.Cartesian3.fromDegrees(asset.lng, asset.lat),
        point: {
          pixelSize: 5,
          color: Cesium.Color.fromCssColorString(ASSET_COLOR).withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.6),
          outlineWidth: 1,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        situationId: situation.id,
      })
    })

    // Outbound ring 3: the countries this anchor's disruption reaches. Country
    // entities carry no coordinate, so the centroid table the other layers
    // already use does the placing.
    situation.rings.ring3_countries.shown.forEach((country, index) => {
      const centroid = COUNTRY_CENTROIDS[country.country_code]
      if (!centroid) return

      const target = { lat: centroid[0], lng: centroid[1] }
      const positions = this._arcPositions(anchor, target)
      if (!positions) return

      this._detail.entities.add({
        id: `sit-exposure-${situation.id}-${index}`,
        polyline: {
          positions: positions,
          width: 1 + Math.min(country.score, 1) * 3.5,
          material: Cesium.Color.fromCssColorString(EXPOSURE_COLOR).withAlpha(0.55),
          arcType: Cesium.ArcType.NONE,
        },
        situationId: situation.id,
      })

      this._detail.entities.add({
        id: `sit-exposure-dot-${situation.id}-${index}`,
        position: Cesium.Cartesian3.fromDegrees(target.lng, target.lat),
        point: {
          pixelSize: 5,
          color: Cesium.Color.fromCssColorString(EXPOSURE_COLOR).withAlpha(0.85),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: country.name,
          font: `400 10px "JetBrains Mono", monospace`,
          fillColor: Cesium.Color.fromCssColorString("#ffd98a"),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -12),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        situationId: situation.id,
      })
    })

    this.viewer.scene.requestRender()
  }

  // Great-circle arc lifted off the surface so convergence is visible from
  // orbit. Cesium's geodesic gives the ground track; the height is ours.
  _arcPositions(from, to) {
    const Cesium = window.Cesium
    if (from.lat == null || to.lat == null) return null
    if (Math.abs(from.lat - to.lat) < 1e-6 && Math.abs(from.lng - to.lng) < 1e-6) return null

    const geodesic = new Cesium.EllipsoidGeodesic(
      Cesium.Cartographic.fromDegrees(from.lng, from.lat),
      Cesium.Cartographic.fromDegrees(to.lng, to.lat)
    )
    const peak = Math.min(geodesic.surfaceDistance * ARC_PEAK_RATIO, ARC_PEAK_MAX_M)
    const positions = []

    for (let i = 0; i <= ARC_SEGMENTS; i++) {
      const t = i / ARC_SEGMENTS
      const point = geodesic.interpolateUsingFraction(t)
      positions.push(Cesium.Cartesian3.fromRadians(
        point.longitude, point.latitude, Math.sin(t * Math.PI) * peak
      ))
    }

    return positions
  }

  _flyTo(situation) {
    const Cesium = window.Cesium
    const points = [situation.anchor, ...situation.members.filter((m) => m.lat != null)]
    const lats = points.map((p) => p.lat)
    const lngs = points.map((p) => p.lng)

    // Members can be a whole hemisphere from the anchor, so framing all of them
    // zooms out to nothing useful. Frame the anchor and let the arcs run off.
    const spread = Math.max(...lats) - Math.min(...lats) + Math.max(...lngs) - Math.min(...lngs)
    const height = Math.min(4_000_000 + spread * 60_000, 20_000_000)

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(situation.anchor.lng, situation.anchor.lat, height),
      duration: 1.2,
    })
  }

  // ── chrome ──────────────────────────────────────────────────────────

  _renderList() {
    this.listTarget.innerHTML = this._situations.map((situation) => {
      const registry = situation.anchor.kind === "registry"
      const selected = situation.id === this._selectedId
      const reach = situation.rings.ring3_countries.total

      return `
        <button type="button" class="sit-row ${selected ? "is-selected" : ""}"
                data-situation-id="${situation.id}"
                data-action="click->situations#selectFromList">
          <span class="sit-row-dot ${registry ? "is-registry" : "is-medoid"}"></span>
          <span class="sit-row-body">
            <span class="sit-row-name">${escapeHtml(situation.name)}</span>
            <span class="sit-row-meta">
              ${pluralize(situation.member_count, "story", "stories")}
              ${reach > 0 ? `· ${reach} countries exposed` : ""}
              ${registry ? "" : "· no place of its own"}
            </span>
          </span>
          ${this._sparkline(situation.daily)}
        </button>`
    }).join("")
  }

  _sparkline(daily) {
    if (!daily?.length) return ""

    const max = Math.max(...daily.map((d) => d.count), 1)
    const width = 54
    const height = 18
    const step = width / daily.length
    const bars = daily.map((day, index) => {
      const barHeight = Math.max((day.count / max) * height, day.count > 0 ? 1.5 : 0)
      return `<rect x="${(index * step).toFixed(1)}" y="${(height - barHeight).toFixed(1)}"
               width="${Math.max(step - 1, 1).toFixed(1)}" height="${barHeight.toFixed(1)}"
               fill="#4fc3f7" opacity="0.75"></rect>`
    }).join("")

    return `<svg class="sit-row-spark" width="${width}" height="${height}" aria-hidden="true">${bars}</svg>`
  }

  _renderPanel(situation) {
    const registry = situation.anchor.kind === "registry"
    const rings = situation.rings
    const ungeocoded = situation.member_count - situation.geo_member_count
    const footprint = this._footprint(situation)

    // The anchor is already the panel title, so the chain spends its width on
    // the rings instead of repeating the name.
    //
    // An occurrence anchors on a real point but is not part of the supply chain:
    // an epicentre has no downstream assets and depends on no commodities, so a
    // chain of three zeroes would read as missing data rather than as the
    // correct answer.
    const reaches = rings.ring1_assets.total + rings.ring2_commodities.total +
      rings.ring3_countries.total

    let chain
    if (!registry) {
      chain = `<div class="sit-note">Grouped on an actor, not a place. The anchor is its most
           central report, not a location this story owns — and it reaches no assets,
           commodities or countries.</div>`
    } else if (reaches === 0) {
      chain = `<div class="sit-note">Measured where it happened, not where it leads. This
           anchor is an occurrence rather than a standing asset, so it carries no
           supply-chain exposure.</div>`
    } else {
      chain = `<div class="sit-chain">
           <span class="sit-chain-node">${rings.ring1_assets.total} assets</span>
           <span class="sit-chain-arrow">→</span>
           <span class="sit-chain-node">${rings.ring2_commodities.total} commodities</span>
           <span class="sit-chain-arrow">→</span>
           <span class="sit-chain-node is-anchor">${rings.ring3_countries.total} countries</span>
         </div>`
    }

    this.panelTarget.innerHTML = `
      <div class="sit-panel-head">
        <div>
          <div class="sit-panel-kicker">${registry ? escapeHtml(situation.concerns.entity_type) : "actor"}</div>
          <div class="sit-panel-title">${escapeHtml(situation.name)}</div>
        </div>
        <button type="button" class="sit-panel-close" data-action="click->situations#close">&times;</button>
      </div>

      <div class="sit-panel-stats">
        <div><b>${situation.member_count}</b> stories · <b>${situation.article_count}</b> reports</div>
        <div><b>${situation.geo_member_count}</b> located${ungeocoded > 0 ? ` · ${ungeocoded} not` : ""}</div>
        <div>${formatDay(situation.first_seen_at)} → ${formatDay(situation.last_seen_at)}</div>
      </div>

      <div class="sit-footprint sit-footprint-${footprint.basis}">
        <span class="sit-footprint-label">Circle on the ground</span>
        <span class="sit-footprint-value">${footprint.label} · ${footprint.basis}</span>
      </div>

      ${chain}

      ${this._ringSection("Countries exposed", rings.ring3_countries, (row) => `
        <span class="sit-ring-name">${escapeHtml(row.name)}</span>
        <span class="sit-ring-detail">${escapeHtml(row.commodities.slice(0, 3).join(", "))}</span>`)}

      ${this._ringSection("Commodities through this anchor", rings.ring2_commodities, (row) => `
        <span class="sit-ring-name">${escapeHtml(row.name)}</span>
        <span class="sit-ring-detail">${(row.score * 100).toFixed(0)}% of flow</span>`)}

      ${this._ringSection("Assets nearby", rings.ring1_assets, (row) => `
        <span class="sit-ring-name">${escapeHtml(row.name)}</span>
        <span class="sit-ring-detail">${row.distance_km != null ? `${row.distance_km.toFixed(0)} km` : escapeHtml(row.entity_type)}</span>`)}

      <div class="sit-section-title">The reports this is made of</div>
      <div class="sit-members">
        ${situation.members.map((member) => `
          <div class="sit-member">
            <div class="sit-member-head">${escapeHtml(member.headline || "(untitled cluster)")}</div>
            <div class="sit-member-meta">
              ${formatDay(member.last_seen_at)} ·
              ${pluralize(member.article_count, "report")} from
              ${pluralize(member.source_count, "source")} ·
              ${escapeHtml(member.event_type)}
              ${member.lat == null ? " · no location" : ""}
            </div>
          </div>`).join("")}
      </div>`

    this.panelTarget.style.display = "block"
    this.panelTarget.scrollTop = 0
  }

  _ringSection(title, ring, rowTemplate) {
    if (!ring.total) return ""

    const more = ring.total - ring.shown.length
    return `
      <div class="sit-section-title">${title} <span class="sit-count">${ring.total}</span></div>
      <div class="sit-ring">
        ${ring.shown.map((row) => `<div class="sit-ring-row">${rowTemplate(row)}</div>`).join("")}
        ${more > 0 ? `<div class="sit-ring-more">+ ${more} more</div>` : ""}
      </div>`
  }

  _setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}

function pluralize(count, noun, plural) {
  const n = Number(count) || 0
  return `${n} ${n === 1 ? noun : plural || `${noun}s`}`
}

function escapeHtml(value) {
  const div = document.createElement("div")
  div.textContent = value == null ? "" : String(value)
  return div.innerHTML
}

function haversineKm(a, b) {
  const rad = Math.PI / 180
  const dLat = (b.lat - a.lat) * rad
  const dLng = (b.lng - a.lng) * rad
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2
  return 6371 * 2 * Math.asin(Math.sqrt(Math.min(h, 1)))
}

function formatDay(iso) {
  if (!iso) return "—"
  return new Date(iso).toISOString().slice(0, 10)
}
