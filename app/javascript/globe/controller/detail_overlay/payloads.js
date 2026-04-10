import {
  chip,
  compactFacts,
  conflictPulseStroke,
  firstPresent,
  kindLabel,
  shortLine,
  toNumber,
} from "globe/controller/detail_overlay/shared"

export function applyDetailOverlayPayloadMethods(GlobeController) {
  GlobeController.prototype._anchoredDetailMarkerStroke = function(kind, data) {
    switch (kind) {
      case "earthquake": {
        const mag = toNumber(data?.mag ?? data?.magnitude) || 0
        if (mag < 3) return "#66bb6a"
        if (mag < 4) return "#ffa726"
        if (mag < 5) return "#ff7043"
        if (mag < 6) return "#ef5350"
        return "#d50000"
      }
      case "natural_event":
        return this.eonetCategoryIcons?.[data?.categoryId]?.color || "#78909c"
      case "news":
        return {
          conflict: "#f44336",
          unrest: "#ff9800",
          disaster: "#ff5722",
          health: "#e91e63",
          economy: "#ffc107",
          diplomacy: "#4caf50",
          cyber: "#7c4dff",
          other: "#90a4ae",
        }[data?.category] || "#90a4ae"
      case "conflict_pulse":
        return conflictPulseStroke(toNumber(data?.pulse_score) || 0)
      case "strategic_situation": {
        return {
          critical: "#ff7043",
          elevated: "#ffca28",
          monitoring: "#26c6da",
        }[data?.status] || "#26c6da"
      }
      case "insight":
        return { critical: "#f44336", high: "#ff9800", medium: "#ffc107", low: "#4caf50" }[data?.severity] || "#8bd8ff"
      case "airport":
        return data?.military ? "#ef5350" : "#ffd54f"
      case "fire_hotspot":
        return data?.strike ? "#e040fb" : (this._isHighConfidenceFire?.(data) ? "#f44336" : "#ff9800")
      case "fire_cluster":
        return data?.strikeCount > 0 ? "#e040fb" : "#ff7043"
      default:
        return firstPresent(data?.markerStroke, data?.markerColor, data?.accentColor, data?.color)
    }
  }

  GlobeController.prototype._anchoredDetailMarkerRadius = function(kind, data) {
    switch (kind) {
      case "conflict_pulse": {
        const score = toNumber(data?.pulse_score) || 0
        const iconSize = score >= 70 ? 48 : score >= 50 ? 44 : 36
        return Math.max(0, iconSize * 0.34 + 3)
      }
      case "strategic_situation":
        return data?.status === "critical" ? 12.5 : 11
      case "insight":
        return 13
      case "news":
        return 10
      case "strike":
        return 12
      case "geoconfirmed":
        return 10
      case "chokepoint":
        return 12
      default:
        return 0
    }
  }

  GlobeController.prototype._anchoredDetailDefaultAltitude = function(kind, data) {
    const explicitAltitude = toNumber(firstPresent(
      data?.altitude,
      data?.alt,
      data?.height,
      data?.currentAlt,
      data?.elevation,
      data?.position?.alt,
    ))
    if (explicitAltitude != null) return explicitAltitude

    switch (kind) {
      case "conflict_pulse":
      case "strategic_situation":
      case "insight":
        return 5600
      case "hex_cell":
        return 5200
      case "news":
      case "news_arc":
      case "strike":
      case "conflict_event":
        return 3200
      case "geoconfirmed":
        return 0
      case "earthquake":
      case "natural_event":
      case "weather_alert":
      case "outage":
      case "chokepoint":
      case "commodity":
        return 2400
      case "ship":
      case "naval_vessel":
      case "train":
      case "webcam":
        return 180
      case "satellite":
        return 25000
      default:
        return 1800
    }
  }

  GlobeController.prototype._buildAnchoredDetailPayload = function(kind, data, options = {}) {
    const anchor = this._anchoredDetailAnchor(kind, data, options)
    const timeLabel = this._anchoredDetailTimeLabel(
      firstPresent(
        data?.time,
        data?.published_at,
        data?.publishedAt,
        data?.event_time,
        data?.effective_start,
        data?.recorded_at,
        data?.updated_at,
        data?.fetched_at,
        data?.created_at,
      )
    )

    const genericTitle = firstPresent(data?.title, data?.name, data?.reason, data?.id, options.id, kindLabel(kind))
    const genericSubtitle = firstPresent(
      data?.location,
      data?.place,
      data?.country && data?.region ? `${data.country} · ${data.region}` : null,
      data?.country,
      data?.region,
      data?.publisher,
      data?.source,
      data?.category,
    )
    const genericFacts = compactFacts([
      firstPresent(data?.status, data?.type_label, data?.event_type, data?.ship_type, data?.severity),
      firstPresent(data?.code, data?.symbol, data?.publisher_name, data?.source),
    ])
    const genericBrief = shortLine(genericFacts.join(" · "))

    const markerStroke = this._anchoredDetailMarkerStroke(kind, data)
    const markerRadius = this._anchoredDetailMarkerRadius(kind, data)

    const makePayload = ({
      title,
      subtitle,
      brief,
      facts = [],
      chips = [],
      accent,
      stroke,
      strokeWidth,
      timeLabel: payloadTimeLabel = timeLabel,
      nodeRequest = null,
      casePath = null,
      focusHeight = null,
      contextAvailable = false,
    }) => ({
      kind,
      title: title || genericTitle,
      subtitle: shortLine(subtitle || genericSubtitle, 84),
      brief: shortLine(brief || compactFacts(facts.length ? facts : genericFacts).join(" · ") || genericBrief),
      facts: compactFacts(facts.length ? facts : genericFacts),
      chips: chips.filter(Boolean).slice(0, 2),
      timeLabel: payloadTimeLabel,
      accent: accent || "#8bd8ff",
      stroke: stroke || markerStroke || accent || "#8bd8ff",
      strokeWidth: strokeWidth || 2.25,
      markerRadius,
      anchor,
      nodeRequest,
      casePath,
      focusHeight,
      contextAvailable,
    })

    switch (kind) {
      case "flight": {
        const emergency = this._isEmergencyFlight?.(data)
        const altitude = toNumber(data?.currentAlt ?? data?.altitude)
        const speed = toNumber(data?.speed ?? data?.velocity)
        return makePayload({
          title: firstPresent(data?.callsign, options.id, data?.registration, "Flight"),
          subtitle: firstPresent(data?.originCountry, data?.registration, data?.aircraftType, "Airborne track"),
          facts: [
            altitude != null ? `${Math.round(altitude).toLocaleString()} m` : null,
            speed != null ? `${Math.round(speed * 3.6)} km/h` : null,
          ],
          chips: [
            chip(emergency ? "Emergency" : (kind === "flight" ? "Flight" : "Track"), emergency ? "critical" : "accent"),
            chip(data?.onGround ? "Ground" : "Airborne", "neutral"),
          ],
          accent: emergency ? "#ff9800" : "#4fc3f7",
        })
      }
      case "ship":
      case "naval_vessel": {
        const speed = toNumber(data?.speed)
        const shipType = this.getShipTypeName?.(data?.shipType)
        return makePayload({
          title: firstPresent(data?.name, data?.mmsi, "Vessel"),
          subtitle: firstPresent(data?.flag, shipType, "Maritime track"),
          facts: [
            speed != null ? `${speed.toFixed(1)} kn` : null,
            firstPresent(data?.destination, data?.mmsi ? `MMSI ${data.mmsi}` : null),
          ],
          chips: [
            chip(kind === "naval_vessel" ? "Naval" : "Ship", kind === "naval_vessel" ? "critical" : "accent"),
            shipType ? chip(shipType, "neutral") : null,
          ],
          accent: kind === "naval_vessel" ? "#ef5350" : "#26c6da",
        })
      }
      case "satellite": {
        return makePayload({
          title: firstPresent(data?.name, data?.norad_id ? `NORAD ${data.norad_id}` : null, "Satellite"),
          subtitle: firstPresent(data?.country, data?.operator, data?.category, "Orbital track"),
          facts: [
            firstPresent(data?.purpose, data?.orbit_type, data?.classification),
            data?.norad_id ? `NORAD ${data.norad_id}` : null,
          ],
          chips: [chip("Satellite", "accent")],
          accent: "#64b5f6",
        })
      }
      case "train": {
        const speed = toNumber(data?.speed_kph ?? data?.speed)
        return makePayload({
          title: firstPresent(data?.line_name, data?.name, data?.id, "Train"),
          subtitle: firstPresent(data?.operator, data?.route_name, data?.origin && data?.destination ? `${data.origin} → ${data.destination}` : null, "Rail service"),
          facts: [
            firstPresent(data?.status, data?.delay_minutes != null ? `${data.delay_minutes} min delay` : null),
            speed != null ? `${Math.round(speed)} km/h` : null,
          ],
          chips: [chip("Train", "accent")],
          accent: "#4fc3f7",
        })
      }
      case "airport": {
        return makePayload({
          title: firstPresent(data?.name, data?.icao || options.id, "Airport"),
          subtitle: firstPresent(data?.municipality && data?.country ? `${data.municipality}, ${data.country}` : null, data?.country, "Airport"),
          facts: [
            data?.icao ? `ICAO ${data.icao}` : options.id ? `ICAO ${options.id}` : null,
            firstPresent(data?.military ? "Military" : null, data?.type),
          ],
          chips: [chip(data?.military ? "Airbase" : "Airport", data?.military ? "critical" : "accent")],
          accent: data?.military ? "#ff7043" : "#ffd54f",
        })
      }
      case "earthquake": {
        const mag = toNumber(data?.mag ?? data?.magnitude)
        const depth = toNumber(data?.depth)
        return makePayload({
          title: mag != null ? `M${mag.toFixed(1)} Earthquake` : firstPresent(data?.title, "Earthquake"),
          subtitle: firstPresent(data?.title, data?.place, "Seismic event"),
          facts: [
            depth != null ? `${depth.toFixed(0)} km depth` : null,
            firstPresent(data?.source, "USGS"),
          ],
          chips: [
            chip(mag != null ? `M${mag.toFixed(1)}` : "Quake", mag >= 5 ? "critical" : mag >= 4 ? "warning" : "accent"),
            chip("Seismic", "neutral"),
          ],
          accent: mag >= 5 ? "#ef5350" : "#ff9800",
        })
      }
      case "natural_event": {
        return makePayload({
          title: firstPresent(data?.title, data?.name, "Natural event"),
          subtitle: firstPresent(data?.category_title, data?.category, data?.location, "Natural event"),
          facts: [
            firstPresent(data?.status, data?.source),
            data?.days ? `${data.days} days active` : null,
          ],
          chips: [chip(firstPresent(data?.category_title, data?.category, "Event"), "warning")],
          accent: "#ff7043",
        })
      }
      case "news": {
        const actors = Array.isArray(data?.actors) ? data.actors.map(actor => actor.name).filter(Boolean) : []
        const location = firstPresent(data?.name, data?.location, data?.place, data?.publisher, data?.origin_source, "Reported event")
        const claimType = data?.claim_event_type ? `${data.claim_event_type}`.replace(/_/g, " ") : null
        const verification = data?.claim_verification_status ? `${data.claim_verification_status}`.replace(/_/g, " ") : null
        return makePayload({
          title: firstPresent(data?.title, data?.name, "News signal"),
          subtitle: location,
          brief: compactFacts([
            firstPresent(claimType, actors.slice(0, 2).join(", ")),
            firstPresent(verification, data?.publisher, data?.source),
          ]).join(" · "),
          chips: [
            chip(firstPresent(data?.category, "News"), data?.threat === "high" ? "critical" : "accent"),
            chip(firstPresent(data?.claim_verification_status, data?.credibility), "neutral"),
          ],
          accent: data?.threat === "high" ? "#ef5350" : "#8bd8ff",
        })
      }
      case "news_arc": {
        return makePayload({
          title: firstPresent(data?.evtName && data?.srcCity ? `${data.srcCity} → ${data.evtName}` : null, data?.evtName, "News flow"),
          subtitle: data?.count ? `${data.count} linked articles` : "Media attention",
          facts: [
            firstPresent(data?.articles?.[0]?.domain, data?.articles?.[0]?.category),
            data?.count ? `${data.count} sources` : null,
          ],
          chips: [chip("News Flow", "warning")],
          accent: "#ffab40",
        })
      }
      case "outage": {
        return makePayload({
          title: firstPresent(data?.name, data?.code, "Internet outage"),
          subtitle: "Internet outage",
          facts: [
            data?.level ? `${`${data.level}`.toUpperCase()} severity` : null,
            data?.score != null ? `Score ${data.score}` : null,
          ],
          chips: [
            chip(firstPresent(data?.level, "Outage"), data?.level === "critical" || data?.level === "severe" ? "critical" : "warning"),
            data?.code ? chip(data.code, "neutral") : null,
          ],
          accent: data?.level === "critical" || data?.level === "severe" ? "#f44336" : "#ffc107",
        })
      }
      case "cable": {
        return makePayload({
          title: firstPresent(data?.name, "Submarine cable"),
          subtitle: "Submarine cable",
          facts: [firstPresent(data?.source, "TeleGeography")],
          chips: [chip("Cable", "accent")],
          accent: "#00bcd4",
        })
      }
      case "pipeline": {
        return makePayload({
          title: firstPresent(data?.name, "Pipeline"),
          subtitle: firstPresent(data?.country, data?.status, "Energy infrastructure"),
          facts: [
            firstPresent(data?.type, data?.status),
            data?.length_km ? `${data.length_km.toLocaleString()} km` : null,
          ],
          chips: [chip(firstPresent(data?.type, "Pipeline"), "warning")],
          accent: data?.color || "#ff6d00",
          nodeRequest: data?.id ? { kind: "pipeline", id: data.id } : options.id ? { kind: "pipeline", id: options.id } : null,
          focusHeight: 1200000,
        })
      }
      case "webcam": {
        return makePayload({
          title: firstPresent(data?.title, "Webcam"),
          subtitle: firstPresent(data?.city && data?.country ? `${data.city}, ${data.country}` : null, data?.country, "Live camera"),
          facts: [firstPresent(data?.source, data?.channel_title), "Live feed"],
          chips: [chip("Camera", "accent")],
          accent: "#4fc3f7",
        })
      }
      case "military_base": {
        return makePayload({
          title: firstPresent(data?.name, "Military base"),
          subtitle: firstPresent(data?.country, data?.branch, "Military site"),
          facts: [firstPresent(data?.type, data?.service), firstPresent(data?.operator, data?.country_code)],
          chips: [chip("Military", "critical")],
          accent: "#ef5350",
        })
      }
      case "airbase": {
        return makePayload({
          title: firstPresent(data?.name, options.id, "Airbase"),
          subtitle: firstPresent(data?.municipality && data?.country ? `${data.municipality}, ${data.country}` : null, data?.country, "Military airbase"),
          facts: [
            options.id ? `ICAO ${options.id}` : null,
            firstPresent(data?.type, data?.elevation ? `${data.elevation} ft` : null),
          ],
          chips: [chip("Airbase", "critical")],
          accent: "#ff7043",
        })
      }
      case "power_plant": {
        return makePayload({
          title: firstPresent(data?.name, "Power plant"),
          subtitle: firstPresent(data?.country, data?.fuel, "Energy site"),
          facts: [
            data?.capacity_mw ? `${Math.round(data.capacity_mw).toLocaleString()} MW` : null,
            firstPresent(data?.fuel, data?.status),
          ],
          chips: [chip(firstPresent(data?.fuel, "Power"), "warning")],
          accent: "#ffb300",
        })
      }
      case "chokepoint": {
        const ships = toNumber(data?.ships_transiting ?? data?.ships_daily ?? data?.ships_nearby?.total)
        return makePayload({
          title: firstPresent(data?.name, "Chokepoint"),
          subtitle: firstPresent(data?.region, data?.status, "Maritime chokepoint"),
          brief: compactFacts([
            ships != null ? `${Math.round(ships)} ships nearby` : null,
            firstPresent(data?.risk_factors?.[0], data?.commodity_signals?.[0]?.symbol),
          ]).join(" · "),
          chips: [
            chip(firstPresent(data?.status, "Monitoring"), data?.status === "critical" ? "critical" : data?.status === "elevated" ? "warning" : "accent"),
            chip("Chokepoint", "neutral"),
          ],
          accent: data?.status === "critical" ? "#f44336" : "#4fc3f7",
          nodeRequest: firstPresent(data?.id, data?.name) ? { kind: "chokepoint", id: firstPresent(data?.id, data?.name) } : null,
          focusHeight: 1000000,
        })
      }
      case "railway": {
        const category = firstPresent(data?.category_label, data?.category != null ? `Category ${data.category}` : null)
        return makePayload({
          title: "Railway",
          subtitle: firstPresent(data?.continent, data?.country, "Rail segment"),
          facts: [category, data?.electrified === 1 ? "Electrified" : "Non-electrified"],
          chips: [chip("Rail", "accent")],
          accent: data?.electrified === 1 ? "#64b5f6" : "#b0bec5",
        })
      }
      case "strike": {
        const isVerified = data?.detectionKind === "verified_strike" || data?.strikeConfidence === "verified" || !!data?.gcMatch
        const confidenceLabel = isVerified
          ? "Verified"
          : data?.strikeConfidence
            ? `${data.strikeConfidence}`.replace(/_/g, " ")
            : null
        const casePayload = this._caseSourcePayloadForStrike?.(data)
        const result = makePayload({
          title: isVerified ? firstPresent(data?.gcMatch?.title, data?.name, data?.title, "Verified strike") : firstPresent(data?.name, data?.title, "Heat signature"),
          subtitle: firstPresent(data?.gcMatch?.region, data?.location_name, data?.country, isVerified ? "Verified strike" : "Thermal detection"),
          brief: compactFacts([
            data?.frp != null ? `${Number(data.frp).toFixed(0)} MW FRP` : null,
            firstPresent(data?.satellite, data?.instrument),
            data?.clusterSize ? `${data.clusterSize + 1} detections nearby` : null,
          ]).join(" • "),
          facts: [
            firstPresent(data?.classification, data?.event_type, data?.satellite),
            firstPresent(confidenceLabel, data?.status, data?.confidence_label),
          ],
          chips: [
            chip(isVerified ? "Verified strike" : "Heat signature", isVerified ? "accent" : "warning"),
            confidenceLabel ? chip(confidenceLabel, "neutral") : null,
          ],
          accent: isVerified ? "#4caf50" : "#e040fb",
          casePath: casePayload && this._caseIntakePathForPayload ? this._caseIntakePathForPayload(casePayload) : null,
        })
        result._strikeData = data
        return result
      }
      case "geoconfirmed": {
        const srcCount = Array.isArray(data?.sourceUrls) ? data.sourceUrls.length : 0
        const result = makePayload({
          title: firstPresent(data?.description, data?.title, "GeoConfirmed event"),
          subtitle: firstPresent(data?.region, "Verified geolocation"),
          facts: [
            srcCount ? `${srcCount} source${srcCount !== 1 ? "s" : ""}` : null,
            firstPresent(data?.region),
          ],
          chips: [
            chip("Verified", "success"),
            chip("GeoConfirmed", "neutral"),
          ],
          accent: "#ff9800",
        })
        result._gcData = data
        return result
      }
      case "strike_arc": {
        return makePayload({
          title: firstPresent(data?.label, data?.name, data?.headline, "Strike arc"),
          subtitle: firstPresent(data?.theater, data?.target_name, data?.origin_name, "Conflict corridor"),
          facts: [
            firstPresent(data?.trend, data?.projectile_type, data?.category),
            firstPresent(data?.source_name, data?.verification_status),
          ],
          chips: [chip("Strike Arc", "critical")],
          accent: "#ef5350",
        })
      }
      case "strategic_situation": {
        const clusterCount = data?.direct_cluster_count != null
          ? `${data.direct_cluster_count} corroborated cluster${data.direct_cluster_count === 1 ? "" : "s"}`
          : null
        const nodeRequest = data?.kind && data?.node_id
          ? { kind: data.kind, id: data.node_id }
          : data?.theater
            ? { kind: "theater", id: data.theater }
            : null
        const casePath = data?.theater && this._caseSourcePayloadForTheater && this._caseIntakePathForPayload
          ? this._caseIntakePathForPayload(this._caseSourcePayloadForTheater({
              ...data,
              theater: data.theater,
              situation_name: data.name,
            }))
          : null
        return makePayload({
          title: firstPresent(data?.name, "Strategic situation"),
          subtitle: firstPresent(data?.theater, data?.country, "Strategic view"),
          brief: compactFacts([
            clusterCount,
            firstPresent(data?.pressure_summary, data?.verification_status, data?.event_type),
          ]).join(" • "),
          chips: [
            chip("Situation", "warning"),
            chip(firstPresent(data?.event_type, data?.verification_status), "neutral"),
          ],
          accent: this._anchoredDetailMarkerStroke(kind, data) || "#ffab40",
          timeLabel: null,
          nodeRequest,
          casePath,
          focusHeight: 1400000,
        })
      }
      case "conflict_pulse": {
        const stroke = conflictPulseStroke(toNumber(data?.pulse_score) || 0)
        const reportCount = data?.count_24h != null
          ? `${data.count_24h} report${data.count_24h === 1 ? "" : "s"} / 24h`
          : null
        const theaterIdentifier = firstPresent(data?.theater, data?.situation_name, data?.conflict_name)
        const casePath = theaterIdentifier && this._caseSourcePayloadForTheater && this._caseIntakePathForPayload
          ? this._caseIntakePathForPayload(this._caseSourcePayloadForTheater(data))
          : null
        return makePayload({
          title: firstPresent(data?.situation_name, data?.theater, data?.conflict_name, "Conflict theater"),
          subtitle: firstPresent(data?.theater, data?.country, "Conflict pulse"),
          brief: compactFacts([
            data?.pulse_score != null ? `Pulse ${Math.round(data.pulse_score)}` : null,
            reportCount,
            firstPresent(data?.top_headlines?.[0], data?.country),
          ]).join(" • "),
          chips: [
            chip(firstPresent(data?.escalation_trend, "Monitoring"), data?.escalation_trend === "surging" || data?.escalation_trend === "escalating" ? "critical" : "warning"),
            chip("Theater", "neutral"),
          ],
          accent: stroke,
          stroke,
          timeLabel: null,
          nodeRequest: theaterIdentifier ? { kind: "theater", id: theaterIdentifier } : null,
          casePath,
          focusHeight: 1500000,
        })
      }
      case "hex_cell": {
        return makePayload({
          title: firstPresent(data?.local_name, data?.theater, "Conflict theater"),
          subtitle: firstPresent(data?.theater, data?.country, "Activity cell"),
          facts: [
            data?.event_count != null ? `${data.event_count} events` : null,
            data?.article_count != null ? `${data.article_count} articles` : null,
          ],
          chips: [chip("Theater", "warning")],
          accent: "#ff7043",
        })
      }
      case "conflict_event": {
        return makePayload({
          title: firstPresent(data?.conflict, data?.headline, "Conflict event"),
          subtitle: firstPresent(data?.country && data?.type_label ? `${data.country} · ${data.type_label}` : null, data?.location, "Conflict event"),
          brief: compactFacts([
            data?.deaths != null ? `${data.deaths} deaths` : null,
            firstPresent(data?.side_a && data?.side_b ? `${data.side_a} vs ${data.side_b}` : null, data?.date_start),
          ]).join(" · "),
          chips: [chip(firstPresent(data?.type_label, "Conflict"), "critical")],
          accent: "#f44336",
        })
      }
      case "traffic": {
        return makePayload({
          title: firstPresent(data?.name, data?.country_name, data?.code, "Internet traffic"),
          subtitle: "Internet traffic snapshot",
          facts: [
            data?.traffic != null ? `${data.traffic.toFixed(2)}% traffic` : null,
            data?.attack_target > 0 ? `${data.attack_target.toFixed(2)}% targeted` : data?.attack_origin > 0 ? `${data.attack_origin.toFixed(2)}% origin` : null,
          ],
          chips: [chip("Traffic", "accent")],
          accent: "#69f0ae",
        })
      }
      case "notam": {
        const low = data?.alt_low_ft?.toLocaleString?.() || "SFC"
        const high = data?.alt_high_ft?.toLocaleString?.()
        return makePayload({
          title: firstPresent(data?.reason, data?.id, "NOTAM"),
          subtitle: firstPresent(data?.id, "Aviation restriction"),
          facts: [
            data?.radius_nm != null ? `${data.radius_nm} NM` : null,
            high ? `${low}–${high} ft` : null,
          ],
          chips: [chip("NOTAM", "critical")],
          accent: "#ef5350",
        })
      }
      case "weather_alert": {
        return makePayload({
          title: firstPresent(data?.event, data?.title, "Weather alert"),
          subtitle: firstPresent(data?.area_desc, data?.sender_name, data?.headline, "Weather alert"),
          facts: [
            firstPresent(data?.severity, data?.urgency),
            firstPresent(data?.certainty, data?.status),
          ],
          chips: [chip(firstPresent(data?.severity, "Alert"), "warning")],
          accent: "#ff9800",
        })
      }
      case "commodity": {
        const price = toNumber(data?.price)
        const change = toNumber(data?.change_pct)
        return makePayload({
          title: firstPresent(data?.name, data?.symbol, "Commodity"),
          subtitle: firstPresent(data?.region, data?.category, "Market signal"),
          brief: compactFacts([
            price != null ? `$${price.toFixed(data?.category === "currency" ? 4 : 2)}` : null,
            change != null ? `${change > 0 ? "+" : ""}${change.toFixed(2)}%` : null,
          ]).join(" · "),
          chips: [chip(firstPresent(data?.category, "Market"), change < 0 ? "critical" : change > 0 ? "accent" : "neutral")],
          accent: change < 0 ? "#ef5350" : change > 0 ? "#4caf50" : "#ffc107",
          nodeRequest: firstPresent(data?.symbol, data?.name) ? { kind: "commodity", id: firstPresent(data?.symbol, data?.name) } : null,
        })
      }
      case "regional_economy": {
        const gdpPerCapita = toNumber(data?.metrics?.gdp_per_capita_usd)
        const manufacturingShare = toNumber(data?.metrics?.manufacturing_share_pct)
        const exportsShare = toNumber(data?.metrics?.exports_goods_services_pct_gdp)
        const selectedMetricValue = toNumber(data?.selected_metric_value)
        const selectedMetricLabel = firstPresent(data?.selected_metric_short_label, data?.selected_metric_label)
        const accent = this._regionalEconomyAccent?.(data) || data?.accent_color || "#b28704"
        const sourceLabel = [data?.source_name, data?.latest_year].filter(Boolean).join(" · ")
        const selectedMetricDisplay = selectedMetricValue != null
          ? (
              data?.selected_metric_key?.includes?.("_usd") ? `$${Math.round(selectedMetricValue).toLocaleString()}` :
              data?.selected_metric_key?.includes?.("_pct") || data?.selected_metric_key === "energy_imports_net_pct_energy_use" ? `${selectedMetricValue.toFixed(1)}%` :
              Math.round(selectedMetricValue).toLocaleString()
            )
          : null

        return makePayload({
          title: firstPresent(data?.country_name, data?.country_code_alpha3, "Regional economy"),
          subtitle: firstPresent(sourceLabel, "Economic baseline"),
          brief: compactFacts([
            selectedMetricLabel && selectedMetricDisplay ? `${selectedMetricLabel} ${selectedMetricDisplay}` : null,
            gdpPerCapita != null ? `GDP/cap $${Math.round(gdpPerCapita).toLocaleString()}` : null,
            exportsShare != null ? `Exports ${exportsShare.toFixed(1)}% GDP` : manufacturingShare != null ? `Mfg ${manufacturingShare.toFixed(1)}%` : null,
          ], 3).join(" · "),
          chips: [
            chip(firstPresent(data?.country_code_alpha3, "Economy"), "warning"),
            chip(firstPresent(selectedMetricLabel, "Baseline"), "neutral"),
          ],
          accent,
          stroke: accent,
          focusHeight: 1200000,
          contextAvailable: true,
        })
      }
      case "regional_admin_economy": {
        const previewScore = toNumber(data?.metrics?.preview_score)
        const cityCount = toNumber(data?.metrics?.city_count)
        const siteCount = toNumber(data?.metrics?.strategic_site_count)
        const powerCapacityMw = toNumber(data?.metrics?.curated_power_capacity_mw)
        const accent = this._regionalAdminEconomyAccent?.(data) || data?.accent_color || "#2f7ea7"
        const selectedSector = data?.selected_sector_profile
        const selectedSectorKey = data?.selected_sector_key
        const selectedSectorLabel = firstPresent(data?.selected_sector_label, selectedSector?.sector_name)
        const selectedRank = data?.selected_rank
        const topSector = Array.isArray(data?.top_sectors) ? data.top_sectors[0] : null
        const focusBrief = selectedSector
          ? compactFacts([
              selectedSectorLabel ? `${selectedSectorLabel}` : null,
              selectedSector?.signal_count != null ? `${selectedSector.signal_count} signals` : null,
              selectedSector?.node_count != null ? `${selectedSector.node_count} nodes` : null,
            ], 3).join(" · ")
          : selectedSectorKey && selectedSectorKey !== "all"
            ? compactFacts([
                selectedSectorLabel ? `${selectedSectorLabel}` : null,
                "No current signal",
              ], 2).join(" · ")
          : compactFacts([
              topSector?.sector_name ? `${topSector.sector_name}` : null,
              previewScore != null ? `Signal ${Math.round(previewScore)}` : null,
              cityCount != null ? `${cityCount} cities` : null,
            ], 3).join(" · ")

        return makePayload({
          title: firstPresent(data?.name, "Admin area"),
          subtitle: firstPresent(
            compactFacts([
              data?.country_name,
              selectedRank?.rank != null && selectedRank?.total != null ? `Rank ${selectedRank.rank}/${selectedRank.total}` : null,
            ], 2).join(" · "),
            data?.country_code_alpha3,
            "Admin area structure"
          ),
          brief: compactFacts([
            focusBrief,
            siteCount != null ? `${siteCount} sites` : null,
            powerCapacityMw != null && powerCapacityMw > 0 ? `${(powerCapacityMw / 1000).toFixed(1)} GW` : null,
          ], 4).join(" · "),
          chips: [
            chip(firstPresent(data?.country_code_alpha3, "Admin"), "warning"),
            chip(firstPresent(selectedSectorLabel, topSector?.sector_name, "Structure"), "neutral"),
          ],
          accent,
          stroke: accent,
          focusHeight: 450000,
          contextAvailable: true,
        })
      }
      case "regional_area_metric": {
        const selectedMetricValue = toNumber(data?.selected_metric_value)
        const selectedMetricLabel = firstPresent(data?.selected_metric_short_label, data?.selected_metric_label)
        const nativeLevel = firstPresent(data?.native_level, "region")
        const accent = this._regionalAdminEconomyAccent?.(data) || data?.accent_color || "#2f7ea7"
        const sourceLabel = compactFacts([
          data?.source_name,
          data?.latest_year,
          nativeLevel,
        ], 3).join(" · ")
        const selectedMetricDisplay = selectedMetricValue != null
          ? (
              data?.selected_metric_key?.includes?.("_usd") ? `$${Math.round(selectedMetricValue).toLocaleString()}` :
              data?.selected_metric_key?.includes?.("_pct") || data?.selected_metric_key === "energy_imports_net_pct_energy_use" ? `${selectedMetricValue.toFixed(1)}%` :
              Math.round(selectedMetricValue).toLocaleString()
            )
          : null

        return makePayload({
          title: firstPresent(data?.name, "Region"),
          subtitle: firstPresent(
            compactFacts([
              data?.country_name,
              nativeLevel,
            ], 2).join(" · "),
            data?.country_code_alpha3,
            "Regional metric"
          ),
          brief: compactFacts([
            selectedMetricLabel && selectedMetricDisplay ? `${selectedMetricLabel} ${selectedMetricDisplay}` : null,
            data?.selected_metric_source || sourceLabel,
          ], 2).join(" · "),
          chips: [
            chip(firstPresent(data?.country_code_alpha3, "Region"), "warning"),
            chip(firstPresent(selectedMetricLabel, "Metric"), "neutral"),
          ],
          accent,
          stroke: accent,
          focusHeight: 450000,
          contextAvailable: true,
        })
      }
      case "regional_municipality": {
        const signalScore = toNumber(data?.signal_score)
        const selectedSectorNames = Array.isArray(data?.selected_sector_names) ? data.selected_sector_names : []
        const accent = data?.accent_color || "#2f7ea7"

        return makePayload({
          title: firstPresent(data?.name, "Municipality"),
          subtitle: firstPresent(
            compactFacts([
              data?.admin_area,
              data?.country_name,
            ], 2).join(" · "),
            data?.country_name,
            "Municipal node"
          ),
          brief: compactFacts([
            data?.selected_sector_label && data?.selected_sector_key !== "all" ? data.selected_sector_label : null,
            signalScore != null ? `Signal ${Math.round(signalScore)}` : null,
            selectedSectorNames.length > 0 ? selectedSectorNames.slice(0, 2).join(" · ") : null,
          ], 3).join(" · "),
          chips: [
            chip(firstPresent(data?.country_code, data?.country_name, "Municipality"), "warning"),
            chip(firstPresent(data?.selected_sector_label, "Municipal"), "neutral"),
          ],
          accent,
          stroke: accent,
          focusHeight: 180000,
          contextAvailable: true,
        })
      }
      case "insight": {
        const theater = firstPresent(data?.entities?.theater?.name, data?.entities?.pulse?.theater, data?.location)
        return makePayload({
          title: firstPresent(data?.title, "Insight"),
          subtitle: firstPresent(theater, data?.category, "Derived insight"),
          brief: firstPresent(
            data?.description,
            data?.summary,
            compactFacts([
              data?.confidence != null ? `${Math.round(data.confidence * 100)}% confidence` : null,
              firstPresent(data?.kind, data?.severity),
            ]).join(" · ")
          ),
          chips: [chip(firstPresent(data?.severity, "Insight"), data?.severity === "critical" ? "critical" : "accent")],
          accent: "#8bd8ff",
        })
      }
      case "fire_hotspot": {
        return makePayload({
          title: "Fire hotspot",
          subtitle: firstPresent(data?.satellite, data?.country, data?.daynight, "Thermal anomaly"),
          facts: [
            firstPresent(data?.confidence, data?.confidence_label),
            firstPresent(data?.brightness, data?.frp != null ? `FRP ${data.frp}` : null),
          ],
          chips: [chip("Fire", "warning")],
          accent: "#ff7043",
        })
      }
      case "fire_cluster": {
        return makePayload({
          title: data?.count != null ? `${data.count} hotspots` : "Fire cluster",
          subtitle: firstPresent(data?.name, data?.country, "Clustered fire activity"),
          facts: [
            firstPresent(data?.confidence, data?.high_confidence_count != null ? `${data.high_confidence_count} high confidence` : null),
            firstPresent(data?.latest_time, data?.satellite),
          ],
          chips: [chip("Fire Cluster", "warning")],
          accent: "#ff8a65",
        })
      }
      default:
        return makePayload({
          title: genericTitle,
          subtitle: genericSubtitle,
          facts: genericFacts,
          chips: [chip(kindLabel(kind), "neutral")],
        })
    }
  }
}
