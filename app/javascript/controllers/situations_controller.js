import { Controller } from "@hotwired/stimulus"
import { COUNTRY_CENTROIDS } from "globe/country_centroids"
import { SituationLayerManager } from "globe/situation_layers"

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

// Screen-space label declutter. Char width is the JetBrains Mono advance at
// the 12px label size -- mono, so a name's box is its length. The gap is
// between label boxes.
const LABEL_CHAR_PX = 7.2
const LABEL_LINE_PX = 16
const LABEL_MIN_GAP = 4

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
    this._layers?.deactivate()
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

    this._layers = new SituationLayerManager(this.viewer)
    // When the boundary layer covers the anchor with a real polygon, the
    // nominal footprint circle is a worse duplicate of it -- hide it until the
    // layer goes away or the selection changes.
    this._layers.onBoundaryState = ({ anchorPolygon }) => this._setFootprintHidden(anchorPolygon)
    this._wirePicking()
    // Labels are placed from screen geometry, which the camera just changed.
    this.viewer.camera.moveEnd.addEventListener(() => this._declutterAnchorLabels())
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
      this._fetchRegions()
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

      const entity = this._anchors.entities.add({
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
      // What the declutter needs to reserve this label's screen box without
      // measuring rendered glyphs.
      entity._labelPin = {
        halfWidth: (situation.name.length * LABEL_CHAR_PX) / 2,
        lineHeight: LABEL_LINE_PX,
        below,
        offset,
      }
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

      entity._labelWanted = selected != null
        ? isSelected
        : registry || isHovered
      entity._labelPriority = isSelected ? 0 : isHovered ? 1 : 2
    })

    this._declutterAnchorLabels()

    // Regions dim with their anchors so the selected story stays the loudest
    // shape on the globe.
    this._regions?.entities.values.forEach((entity) => {
      const dimmed = selected != null && !entity.regionSituationIds?.includes(selected)
      if (entity.polygon) {
        entity.polygon.material = Cesium.Color.fromCssColorString(REGISTRY_COLOR)
          .withAlpha(dimmed ? 0.03 : 0.1)
      }
      if (entity.polyline) {
        entity.polyline.material = Cesium.Color.fromCssColorString("#fff6e0")
          .withAlpha(dimmed ? 0.15 : 0.6)
      }
    })

    this.viewer.scene.requestRender()
  }

  // The alternation above separates a pair of neighbours; it does nothing for
  // eleven situations anchored to the same Bangkok centroid, which painted two
  // rows of overprinted names. Styling decides which labels deserve to exist
  // (_labelWanted); this decides which of those fit on screen -- selected
  // first, then hovered, then rail order, keeping a label only when its box
  // clears everything already kept and its anchor is on the near side of the
  // globe. A name that loses its slot is still one hover away.
  _declutterAnchorLabels() {
    const Cesium = window.Cesium
    const scene = this.viewer?.scene
    const entities = this._anchors?.entities.values
    if (!Cesium || !scene || !entities?.length) return

    const toWindow = Cesium.SceneTransforms.worldToWindowCoordinates
      || Cesium.SceneTransforms.wgs84ToWindowCoordinates
    const time = this.viewer.clock.currentTime
    const occluder = new Cesium.EllipsoidalOccluder(Cesium.Ellipsoid.WGS84, scene.camera.positionWC)
    const candidates = entities
      .filter((entity) => entity.label && entity._labelPin)
      .sort((a, b) => (a._labelPriority ?? 2) - (b._labelPriority ?? 2))
    const kept = []

    for (const entity of candidates) {
      if (!entity._labelWanted) {
        entity.label.show = false
        continue
      }
      const position = entity.position?.getValue(time)
      const win = position && occluder.isPointVisible(position) && toWindow(scene, position)
      if (!win) {
        entity.label.show = false
        continue
      }
      const pin = entity._labelPin
      const top = pin.below ? win.y + pin.offset : win.y - pin.offset - pin.lineHeight
      const box = {
        left: win.x - pin.halfWidth,
        right: win.x + pin.halfWidth,
        top,
        bottom: top + pin.lineHeight,
      }
      const clear = !kept.some((other) => (
        box.left < other.right + LABEL_MIN_GAP
        && box.right + LABEL_MIN_GAP > other.left
        && box.top < other.bottom + LABEL_MIN_GAP
        && box.bottom + LABEL_MIN_GAP > other.top
      ))
      entity.label.show = clear
      if (clear) kept.push(box)
    }

    scene.requestRender()
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
  // One line of structured fact under a report: who → whom, or the single
  // named party. The event type already sits in the meta line above, so this
  // renders only when there is an actor to show.
  _memberClaimHtml(member) {
    const claim = member.claim
    if (!claim) return ""

    if (claim.initiator && claim.target) {
      return `<div class="sit-member-claim">${escapeHtml(claim.initiator)}
        <span class="sit-fact-arrow">→</span> ${escapeHtml(claim.target)}</div>`
    }
    const solo = claim.initiator || claim.subject
    return solo ? `<div class="sit-member-claim">${escapeHtml(solo)}</div>` : ""
  }

  // The structured reading of the situation: who its member stories say is
  // acting on whom, and what kind of events they describe. Counts are member
  // stories. Rendered only when the extraction produced something -- an empty
  // facts box would just advertise the pipeline.
  _factsHtml(situation) {
    const facts = situation.facts
    if (!facts) return ""

    const pairs = facts.pairs?.length ? this._pairRowsHtml(facts.pairs) : ""

    const kinds = (facts.kinds || []).map((k) =>
      `<span class="sit-fact-kind">${escapeHtml(String(k.kind).replace(/_/g, " "))} · ${k.count}</span>`
    ).join("")

    if (!pairs && !kinds) return ""

    return `
      <div class="sit-facts">
        ${pairs ? `<div class="sit-section-title">Who acts on whom</div>${pairs}` : ""}
        ${kinds ? `<div class="sit-fact-kinds">${kinds}</div>` : ""}
      </div>`
  }

  // How the story broke: one bar per hour or day of reports, an amber tick
  // under the buckets where an outlet filed its first report. Echo grows the
  // bars; corroboration moves the ticks. Rendered only when there are enough
  // stamped reports to draw a shape worth reading.
  _timelineHtml(situation) {
    const timeline = situation.timeline
    if (!timeline?.points?.length) return ""

    const points = timeline.points
    const width = 288
    const chartHeight = 34
    const height = chartHeight + 6
    const step = width / points.length
    const barWidth = Math.max(step - 1, 1)
    const max = Math.max(...points.map((point) => point.articles), 1)

    const bars = points.map((point, index) => {
      const x = (index * step).toFixed(1)
      const barHeight = Math.max((point.articles / max) * chartHeight, point.articles > 0 ? 1.5 : 0)
      const bar = point.articles > 0
        ? `<rect x="${x}" y="${(chartHeight - barHeight).toFixed(1)}" width="${barWidth.toFixed(1)}"
             height="${barHeight.toFixed(1)}" fill="#4fc3f7" opacity="0.8"></rect>`
        : ""
      const tick = point.new_sources > 0
        ? `<rect x="${x}" y="${chartHeight + 3}" width="${barWidth.toFixed(1)}" height="3"
             fill="#ffb300"></rect>`
        : ""
      return bar + tick
    }).join("")

    return `
      <div class="sit-timeline">
        <div class="sit-section-title">How it broke</div>
        <svg width="${width}" height="${height}" aria-hidden="true">${bars}</svg>
        <div class="sit-timeline-caption">
          <span>${formatDay(timeline.first_at)} → ${formatDay(points[points.length - 1].t)}</span>
          <span>reports per ${timeline.bucket} · peak ${max}
            · <span class="sit-timeline-tick">▊</span> new source</span>
        </div>
      </div>`
  }

  // Who says who did it: the split the modal answer hides. The server only
  // sends this when outlets disagree on the initiator, so its presence is
  // itself the signal -- attribution is contested, and the bars show by how
  // much. Sources, not reports, drive the bar: ten echoes of one wire should
  // not out-shout three independent newsrooms.
  _attributionHtml(situation) {
    const rows = situation.attribution
    if (!rows?.length) return ""

    return `
      <div class="sit-attribution">
        <div class="sit-section-title">Who says who did it · contested</div>
        ${this._attributionRowsHtml(rows)}
      </div>`
  }

  // What the numbers are doing: each dot is a figure some stamped headline
  // asserted, the line is the highest figure asserted so far. A dot under
  // the line is a correction or a straggler quoting an old count -- exactly
  // the disagreement worth seeing, so the raw dots stay visible instead of
  // being folded into the maximum.
  _figuresHtml(situation) {
    const figures = situation.figures
    if (!figures) return ""

    const charts = ["killed", "injured", "missing"].filter((kind) => figures[kind]?.length)
      .slice(0, 2).map((kind) => {
        const points = figures[kind]
        const width = 288
        const chartHeight = 40
        const times = points.map((point) => Date.parse(point.t))
        const t0 = Math.min(...times)
        const span = Math.max(Math.max(...times) - t0, 1)
        const max = Math.max(...points.map((point) => point.value), 1)
        const x = (t) => 4 + ((Date.parse(t) - t0) / span) * (width - 8)
        const y = (v) => chartHeight - 3 - (v / max) * (chartHeight - 8)

        let running = 0
        const steps = points.map((point) => {
          running = Math.max(running, point.value)
          return `${x(point.t).toFixed(1)},${y(running).toFixed(1)}`
        })
        const line = `<polyline points="${steps.join(" ")}" fill="none" stroke="#ffb300"
          stroke-width="1.5" opacity="0.9"></polyline>`
        const dots = points.map((point) => `
          <circle cx="${x(point.t).toFixed(1)}" cy="${y(point.value).toFixed(1)}" r="2.5"
            fill="#4fc3f7" opacity="0.9"></circle>`).join("")
        const latest = points[points.length - 1]
        const peak = Math.max(...points.map((point) => point.value))

        return `
          <div class="sit-figures-chart">
            <svg width="${width}" height="${chartHeight}" aria-hidden="true">${line}${dots}</svg>
            <div class="sit-timeline-caption">
              <span>reported ${kind}</span>
              <span>${points[0].value} first → ${latest.value} latest${peak !== latest.value
                ? ` · peak ${peak}` : ""}${latest.qualifier === "at_least" ? " (at least)" : ""}</span>
            </div>
          </div>`
      })
    if (!charts.length) return ""

    return `
      <div class="sit-figures">
        <div class="sit-section-title">What the numbers are doing</div>
        ${charts.join("")}
      </div>`
  }

  // Who is reporting it: the breadth behind the report count. The stats line
  // already carries the number of sources; this names the heaviest outlets
  // and says how many countries they file from, which is the difference
  // between one wire echoing and independent corroboration.
  _sourcesHtml(situation) {
    const sources = situation.sources
    if (!sources?.total) return ""

    if (!sources.top?.length) return ""

    return `
      <div class="sit-sources">
        <div class="sit-section-title">Who is reporting it${sources.countries > 1
          ? ` · ${sources.countries} countries` : ""}</div>
        ${this._sourceChipsHtml(sources)}
      </div>`
  }

  _pairRowsHtml(pairs) {
    const pairMax = Math.max(...pairs.map((pair) => pair.count), 1)
    return pairs.map((pair) => `
      <div class="sit-fact-row">
        <span class="sit-fact-actor">${escapeHtml(pair.from)}</span>
        <span class="sit-fact-arrow">→</span>
        <span class="sit-fact-actor">${escapeHtml(pair.to)}</span>
        <span class="sit-fact-bar"><i style="width:${Math.round((pair.count / pairMax) * 100)}%"></i></span>
        <span class="sit-fact-count">${pair.count === 1 ? "1 story" : `${pair.count} stories`}</span>
      </div>`).join("")
  }

  _attributionRowsHtml(rows) {
    const max = Math.max(...rows.map((row) => row.sources), 1)
    return rows.map((row) => `
      <div class="sit-fact-row">
        <span class="sit-fact-actor">${escapeHtml(row.actor)}</span>
        <span class="sit-fact-bar"><i style="width:${Math.round((row.sources / max) * 100)}%"></i></span>
        <span class="sit-fact-count">${pluralize(row.sources, "source")} · ${pluralize(row.reports, "report")}</span>
      </div>`).join("")
  }

  _sourceChipsHtml(sources) {
    return `<div class="sit-source-chips">${(sources.top || []).map((source) => `
      <span class="sit-source-chip">${escapeHtml(source.name)}${source.country
        ? ` <span class="sit-source-cc">${escapeHtml(String(source.country).toUpperCase())}</span>`
        : ""} · ${source.reports}</span>`).join("")}</div>`
  }

  // ── the composed dossier: the curator edits, the data asserts ───────
  //
  // Everything written (lead, dek, titles, captions, annotations) arrives
  // from the curator already validated server-side; everything numeric is
  // drawn from the same payload the fallback sections read. Voice renders
  // in serif, instrument in mono -- a reader can always tell which is which.
  _composedHtml(situation, composition) {
    const provenance = `
      <div class="sit-composed-prov">
        ${pluralize(situation.member_count, "story", "stories")} ·
        ${pluralize(situation.article_count, "report")} ·
        ${pluralize(situation.source_count, "source")} ·
        ${formatDay(situation.first_seen_at)} → ${formatDay(situation.last_seen_at)}
      </div>`

    const head = `
      <div class="sit-composed-kicker">
        <span class="${situation.tier === "emerging" ? "sit-tier-emerging" : "sit-tier-corroborated"}">${situation.tier}</span>
        ${composition.angle ? `<span>${escapeHtml(composition.angle)}</span>` : ""}
      </div>
      <h3 class="sit-composed-lead">${escapeHtml(composition.lead)}</h3>
      ${composition.dek ? `<p class="sit-composed-dek">${escapeHtml(composition.dek)}</p>` : ""}
      ${provenance}`

    if (composition.treatment === "note") {
      return `${head}
        ${composition.upgrade ? `
          <div class="sit-composed-upgrade"><b>What would change this:</b>
          ${escapeHtml(composition.upgrade)}</div>` : ""}`
    }

    const modules = (composition.modules || [])
      .map((module) => this._composedModuleHtml(situation, module)).join("")
    return head + modules
  }

  _composedModuleHtml(situation, module) {
    const body = this._composedModuleBody(situation, module)
    if (!body) return ""

    return `
      <div class="sit-composed-module is-${module.emphasis || "support"}">
        ${module.title ? `<div class="sit-composed-title">${escapeHtml(module.title)}</div>` : ""}
        ${module.caption ? `<div class="sit-composed-caption">${escapeHtml(module.caption)}</div>` : ""}
        ${body}
      </div>`
  }

  _composedModuleBody(situation, module) {
    switch (module.kind) {
      case "figures_chart": {
        const points = situation.figures?.[module.metric]
        return points?.length
          ? this._revisionChartSvg(points, {
              hero: module.emphasis === "hero", annotations: module.annotations })
          : null
      }
      case "attention_timeline": {
        const timeline = situation.timeline
        return timeline?.points?.length
          ? this._attentionChartSvg(timeline, {
              hero: module.emphasis === "hero", annotations: module.annotations })
          : null
      }
      case "attribution_split":
        return situation.attribution?.length ? this._attributionRowsHtml(situation.attribution) : null
      case "actor_pairs":
        return situation.facts?.pairs?.length ? this._pairRowsHtml(situation.facts.pairs) : null
      case "sources":
        return situation.sources?.top?.length ? this._sourceChipsHtml(situation.sources) : null
      default:
        return null
    }
  }

  // The revision curve as a step line: an assertion holds until a new one
  // revises it, because interpolating between two headlines would invent
  // values nobody reported. Dots are the raw assertions, each real.
  _revisionChartSvg(points, { hero = false, annotations = null } = {}) {
    const width = 288
    const chartHeight = hero ? 64 : 38
    const padTop = annotations?.length ? 14 + (annotations.length - 1) * 11 : 4
    const height = chartHeight + padTop + 4
    const times = points.map((point) => Date.parse(point.t))
    const t0 = Math.min(...times)
    const span = Math.max(Math.max(...times) - t0, 1)
    const max = Math.max(...points.map((point) => point.value), 1)
    const x = (t) => 4 + ((Date.parse(t) - t0) / span) * (width - 8)
    const y = (v) => padTop + chartHeight - 3 - (v / max) * (chartHeight - 8)

    let running = 0
    const steps = []
    points.forEach((point) => {
      const px = x(point.t)
      if (steps.length) steps.push(`${px.toFixed(1)},${steps[steps.length - 1].split(",")[1]}`)
      running = Math.max(running, point.value)
      steps.push(`${px.toFixed(1)},${y(running).toFixed(1)}`)
    })
    const line = `<polyline points="${steps.join(" ")}" fill="none" stroke="#ffb300"
      stroke-width="1.5" opacity="0.9"></polyline>`
    const dots = points.map((point) => `
      <circle cx="${x(point.t).toFixed(1)}" cy="${y(point.value).toFixed(1)}" r="2.5"
        fill="#4fc3f7" opacity="0.9"></circle>`).join("")

    return `<svg class="sit-composed-chart" viewBox="0 0 ${width} ${height}" aria-hidden="true">
      ${line}${dots}${this._annotationMarksSvg(annotations, x, padTop, chartHeight)}</svg>`
  }

  _attentionChartSvg(timeline, { hero = false, annotations = null } = {}) {
    const points = timeline.points
    const width = 288
    const chartHeight = hero ? 56 : 34
    const padTop = annotations?.length ? 14 + (annotations.length - 1) * 11 : 4
    const height = chartHeight + padTop + 4
    const step = width / points.length
    const barWidth = Math.max(step - 1, 1)
    const max = Math.max(...points.map((point) => point.articles), 1)
    const x = (t) => {
      const index = points.findIndex((point) => Date.parse(point.t) >= Date.parse(t))
      return (index < 0 ? points.length - 1 : index) * step + barWidth / 2
    }

    const bars = points.map((point, index) => {
      if (!point.articles) return ""
      const barHeight = Math.max((point.articles / max) * chartHeight, 1.5)
      return `<rect x="${(index * step).toFixed(1)}" y="${(padTop + chartHeight - barHeight).toFixed(1)}"
        width="${barWidth.toFixed(1)}" height="${barHeight.toFixed(1)}" fill="#4fc3f7" opacity="0.8"></rect>`
    }).join("")

    return `<svg class="sit-composed-chart" viewBox="0 0 ${width} ${height}" aria-hidden="true">
      ${bars}${this._annotationMarksSvg(annotations, x, padTop, chartHeight)}</svg>`
  }

  // Written moments pinned to the time axis. Each annotation gets its own
  // row in the reserved strip above the chart -- staggered by index, because
  // two moments close in time would otherwise write over each other.
  _annotationMarksSvg(annotations, x, padTop, chartHeight) {
    if (!annotations?.length) return ""

    return annotations.map((annotation, index) => {
      const px = Math.min(Math.max(x(annotation.t), 6), 282)
      const anchor = px > 200 ? "end" : "start"
      const rowY = padTop - 4 - (annotations.length - 1 - index) * 11
      return `
        <line x1="${px.toFixed(1)}" y1="${(rowY + 2).toFixed(1)}" x2="${px.toFixed(1)}"
          y2="${padTop + chartHeight - 3}" stroke="#3a4656" stroke-width="1"
          stroke-dasharray="2,2"></line>
        <text x="${(px + (anchor === "end" ? -3 : 3)).toFixed(1)}" y="${rowY.toFixed(1)}"
          text-anchor="${anchor}" font-size="9"
          font-family="ui-monospace, Menlo, monospace" fill="#c3ccd6">${escapeHtml(annotation.text)}</text>`
    }).join("")
  }

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
      this._hideOverlapChooser()
      const picked = this.viewer.scene.pick(click.position)

      // Layer data is clickable in its own right: planes and ships track
      // (click again to let go), cameras and quakes open their pages --
      // without re-selecting the situation underneath.
      const flight = picked?.id?.flightRef
      if (flight) return this._layers?.trackFlight(flight)
      const ship = picked?.id?.shipRef
      if (ship) return this._layers?.trackShip(ship)
      const url = picked?.id?.openUrl
      if (url) return window.open(url, "_blank", "noopener")

      // Situations pile up -- Kyiv and a mis-geocoded monument sit 6 km apart.
      // Drill through the click: one anchor selects, several offer a choice.
      const drilled = this.viewer.scene.drillPick(click.position, 8)
      const anchorIds = [...new Set(drilled
        .filter((p) => typeof p?.id?.id === "string" && p.id.id.startsWith("sit-"))
        .map((p) => p.id.situationId)
        .filter((sid) => sid != null))]

      if (anchorIds.length > 1) return this._showOverlapChooser(anchorIds, click.position)
      if (anchorIds.length === 1) return this.select(anchorIds[0])

      // A shared region (Hamas and Gaza both live in the Gaza Strip) offers
      // the same choice a stack of anchors does.
      const regionIds = picked?.id?.regionSituationIds
      if (regionIds?.length > 1) return this._showOverlapChooser(regionIds, click.position)

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

  // ── board regions ───────────────────────────────────────────────────

  // The admin-1 region containing each anchor, drawn for every situation the
  // server could resolve -- a real shape where the board used to guess with a
  // circle. Sea anchors (straits) and unresolvable coordinates stay dots.
  async _fetchRegions() {
    try {
      const resp = await fetch("/api/situations/regions")
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
      const data = await resp.json()
      await this._renderRegions(data.features || [])
    } catch (error) {
      console.error("Situation regions fetch failed", error)
    }
  }

  async _renderRegions(features) {
    const Cesium = window.Cesium
    if (!this._regions) {
      this._regions = new Cesium.CustomDataSource("situation-regions")
      await this.viewer.dataSources.add(this._regions)
    }
    this._regions.entities.removeAll()
    this._regionIds = new Set()

    features.forEach((feature) => {
      const ids = feature.properties?.situation_ids || []
      if (!ids.length) return
      ids.forEach((id) => this._regionIds.add(id))

      this._outerRings(feature.geometry).forEach((ring) => {
        const positions = ring.map(([lng, lat]) => Cesium.Cartesian3.fromDegrees(lng, lat))
        const polygon = this._regions.entities.add({
          polygon: {
            hierarchy: new Cesium.PolygonHierarchy(positions),
            material: Cesium.Color.fromCssColorString(REGISTRY_COLOR).withAlpha(0.1),
            height: 0,
          },
        })
        const outline = this._regions.entities.add({
          polyline: {
            positions: positions,
            width: 1.5,
            material: Cesium.Color.fromCssColorString("#fff6e0").withAlpha(0.6),
            clampToGround: false,
          },
        })
        // One region can cover several situations (Hamas and Gaza share the
        // Gaza Strip); a click on it offers the same chooser stacked anchors
        // get.
        polygon.situationId = ids[0]
        polygon.regionSituationIds = ids
        outline.situationId = ids[0]
        outline.regionSituationIds = ids
      })
    })

    this._syncFootprints()
    this._applyAnchorStyling()
    this.viewer?.scene.requestRender()
  }

  _outerRings(geometry) {
    if (!geometry) return []
    if (geometry.type === "Polygon") return [geometry.coordinates[0]].filter(Boolean)
    if (geometry.type === "MultiPolygon") return geometry.coordinates.map((poly) => poly[0]).filter(Boolean)
    return []
  }

  // The boundary polygon, the board region and the nominal circle all say the
  // same thing; when a real shape is on screen the circle only blurs it.
  _setFootprintHidden(hidden) {
    this._boundaryHidesFootprint = hidden
    this._syncFootprints()
  }

  _syncFootprints() {
    this._anchors?.entities.values.forEach((entity) => {
      if (!entity.ellipse) return
      const id = entity.situationId
      const covered = this._regionIds?.has(id) ||
        (id === this._selectedId && this._boundaryHidesFootprint)
      entity.ellipse.show = !covered
    })
    this.viewer?.scene.requestRender()
  }

  _showOverlapChooser(ids, position) {
    this._hideOverlapChooser()
    const rows = ids.map((id) => {
      const situation = this._situations.find((s) => s.id === id)
      if (!situation) return ""
      return `<button type="button" class="sit-overlap-row" data-situation-id="${situation.id}">
        ${escapeHtml(situation.name)}<span>${situation.member_count} stories</span>
      </button>`
    }).join("")

    const chooser = document.createElement("div")
    chooser.className = "sit-overlap-chooser"
    chooser.innerHTML = rows
    chooser.style.left = `${Math.round(position.x + 12)}px`
    chooser.style.top = `${Math.round(position.y + 12)}px`
    chooser.addEventListener("click", (event) => {
      const id = Number(event.target.closest("[data-situation-id]")?.dataset.situationId)
      if (id) this.select(id)
    })
    this.element.appendChild(chooser)
    this._overlapChooser = chooser
  }

  _hideOverlapChooser() {
    this._overlapChooser?.remove()
    this._overlapChooser = null
  }

  selectFromList(event) {
    this.select(Number(event.currentTarget.dataset.situationId))
  }

  select(id) {
    const situation = this._situations.find((s) => s.id === id)
    if (!situation) return

    this._hideOverlapChooser()
    this._setFootprintHidden(false)
    this._selectedId = id
    this._drawDetail(situation)
    this._renderPanel(situation)
    this._renderList()
    this._applyAnchorStyling()
    this._flyTo(situation)
    // Fire-and-forget: the dossier is complete without the live layers, and
    // the chip bar reports its own failures. When the plan does arrive it
    // carries the curator's judgement -- prose brief, story scope, related
    // situations -- which refines what is already on screen.
    this._layers?.activate(situation)
      .then((plan) => { if (plan && this._selectedId === id) this._applyPlan(situation, plan) })
      .catch((error) => console.error("Layers failed", error))
  }

  _clearSelection() {
    this._hideOverlapChooser()
    this._setFootprintHidden(false)
    this._selectedId = null
    this._layers?.deactivate()
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
      // A country-precision coordinate is a guess at national scale, not a
      // measured point -- draw it at half strength so the eye reads the
      // difference instead of trusting both equally.
      const coarse = member.geo_precision === "country" || member.geo_precision === "unknown"
      const alpha = (0.25 + 0.55 * (1 - Math.min(age, 1))) * (coarse ? 0.45 : 1)
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
          pixelSize: coarse ? 3 : 4,
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

  // Frame the story's scope, not its reporting. Member reports can sit a
  // hemisphere from the anchor (Washington reporting on Hormuz), and framing
  // them zoomed a hyper-local story out to a continent. The camera now fits
  // the situation's radius -- the curator's judgement of how far relevant
  // context extends, refined by _applyPlan when the plan arrives; until then,
  // the measured footprint or the 150 km default stands in.
  _flyTo(situation, radiusKm = null) {
    const Cesium = window.Cesium
    const km = radiusKm || situation.concerns?.radius_km || 150
    const height = this._heightForRadius(km)

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(situation.anchor.lng, situation.anchor.lat, height),
      duration: 1.2,
    })
    this._framedRadiusKm = km
  }

  // Height at which a circle of this radius fills most of the view, with room
  // around it for the layer data at the box edges.
  _heightForRadius(km) {
    return Math.min(Math.max(km * 1000 * 2.6, 200_000), 20_000_000)
  }

  // The plan is the curator's read of the story. Three of its fields land
  // outside the chip bar: the prose brief leads the panel, related situations
  // become links and quiet arcs, and the story's scope re-frames the camera
  // when it disagrees with the geometric first guess.
  _applyPlan(situation, plan) {
    const Cesium = window.Cesium

    if (plan.radius_km && this._framedRadiusKm) {
      const ratio = plan.radius_km / this._framedRadiusKm
      if (ratio > 1.3 || ratio < 0.7) this._flyTo(situation, plan.radius_km)
    }

    const reading = document.getElementById("sit-reading")
    if (reading && plan.composition?.lead) {
      reading.innerHTML = this._composedHtml(situation, plan.composition)
    }

    const brief = document.getElementById("sit-brief")
    if (brief && plan.brief && !plan.composition?.lead) {
      brief.innerHTML = `${escapeHtml(plan.brief)} <span class="sit-brief-basis">AI brief</span>`
      brief.style.display = "block"
    }

    const related = document.getElementById("sit-related")
    if (related && plan.related?.length) {
      related.innerHTML = `
        <div class="sit-section-title">Possibly the same story</div>
        ${plan.related.map((row) => `
          <button type="button" class="sit-related-row" data-situation-id="${row.id}"
                  data-action="click->situations#selectFromList" title="${escapeAttr(row.reason || "")}">
            <span class="sit-ring-name">${escapeHtml(row.name)}</span>
            <span class="sit-ring-detail">${row.distance_km} km · ${escapeHtml(row.reason || "")}</span>
          </button>`).join("")}`
    }

    // A related situation is a claim about two anchors, so it is drawn as a
    // line between them -- dashed and dim, an association rather than evidence.
    ;(plan.related || []).forEach((row, index) => {
      if (row.anchor?.lat == null) return
      const positions = this._arcPositions(situation.anchor, row.anchor)
      if (!positions) return

      this._detail.entities.add({
        id: `sit-related-${situation.id}-${index}`,
        polyline: {
          positions: positions,
          width: 1,
          material: new Cesium.PolylineDashMaterialProperty({
            color: Cesium.Color.fromCssColorString(MEDOID_COLOR).withAlpha(0.55),
            dashLength: 12,
          }),
          arcType: Cesium.ArcType.NONE,
        },
        situationId: situation.id,
      })
    })

    this.viewer.scene.requestRender()
  }

  // ── chrome ──────────────────────────────────────────────────────────

  _renderList() {
    // The payload arrives corroborated-first; emerging situations render below
    // a divider, dimmed, instead of being hidden — thin sourcing is a signal
    // worth seeing, just not one worth leading with.
    const corroborated = this._situations.filter((s) => s.tier !== "emerging")
    const emerging = this._situations.filter((s) => s.tier === "emerging")

    this.listTarget.innerHTML = [
      corroborated.map((situation) => this._listRow(situation)).join(""),
      emerging.length ? `<div class="sit-list-divider">Emerging · thin sourcing</div>` : "",
      emerging.map((situation) => this._listRow(situation)).join("")
    ].join("")
  }

  _listRow(situation) {
    const registry = situation.anchor.kind === "registry"
    const selected = situation.id === this._selectedId
    const reach = situation.rings.ring3_countries.total

    return `
      <button type="button" class="sit-row ${selected ? "is-selected" : ""} ${situation.tier === "emerging" ? "is-emerging" : ""}"
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

    // Prose leads; controls and reference material follow. The brief and the
    // related list are empty shells here -- _applyPlan fills them when the
    // curator's plan arrives, which is usually instant off the warm cache.
    this.panelTarget.innerHTML = `
      <div class="sit-panel-head">
        <div>
          <div class="sit-panel-kicker">${registry ? escapeHtml(situation.concerns.entity_type) : "actor"}</div>
          <div class="sit-panel-title">${escapeHtml(situation.name)}</div>
        </div>
        <button type="button" class="sit-panel-close" data-action="click->situations#close">&times;</button>
      </div>

      <div id="sit-brief" class="sit-brief" style="display:none"></div>

      <div id="sit-reading">
        <div class="sit-panel-stats">
          <div><b>${situation.member_count}</b> stories · <b>${situation.article_count}</b> reports · <b>${situation.source_count}</b> sources${situation.tier === "emerging" ? ` · <span class="sit-tier-emerging">emerging</span>` : ""}
          · ${formatDay(situation.first_seen_at)} → ${formatDay(situation.last_seen_at)}</div>
        </div>

        ${this._timelineHtml(situation)}

        ${this._factsHtml(situation)}

        ${this._attributionHtml(situation)}

        ${this._figuresHtml(situation)}

        ${this._sourcesHtml(situation)}
      </div>

      <div id="sit-related"></div>

      <div class="sit-section-title">The reports this is made of</div>
      <div class="sit-members">
        ${situation.members.map((member) => `
          <div class="sit-member">
            <div class="sit-member-head">${member.url
              ? `<a href="${escapeAttr(member.url)}" target="_blank" rel="noopener">${escapeHtml(member.headline || "(untitled cluster)")}</a>`
              : escapeHtml(member.headline || "(untitled cluster)")}</div>
            <div class="sit-member-meta">
              ${formatDay(member.last_seen_at)} ·
              ${pluralize(member.article_count, "report")} from
              ${pluralize(member.source_count, "source")} ·
              ${escapeHtml(member.event_type)}
              ${member.lat == null
                ? " · no location"
                : member.place
                  ? ` · ${escapeHtml(member.place)}${member.geo_precision === "country" ? " (country-level)" : ""}`
                  : member.geo_precision === "country" || member.geo_precision === "unknown"
                    ? " · location approximate"
                    : ""}
            </div>
            ${this._memberClaimHtml(member)}
          </div>`).join("")}
      </div>

      <div id="sit-layer-chips"></div>
      <div id="sit-layer-sections"></div>

      <details class="sit-exposure">
        <summary>Exposure &amp; footprint${ungeocoded > 0 ? ` · ${situation.geo_member_count}/${situation.member_count} located` : ""}</summary>

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
      </details>`

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

function escapeAttr(value) {
  return escapeHtml(value).replaceAll('"', "&quot;")
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
