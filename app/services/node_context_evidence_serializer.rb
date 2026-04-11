class NodeContextEvidenceSerializer
  class << self
    def serialize(evidence)
      new(evidence).serialize
    end
  end

  def initialize(evidence)
    @evidence = evidence
  end

  def serialize
    case @evidence
    when NewsStoryCluster
      news_story_cluster
    when NewsArticle
      news_article
    when CommodityPrice
      commodity_price
    when Earthquake
      earthquake
    when FireHotspot
      fire_hotspot
    when NaturalEvent
      natural_event
    when GeoconfirmedEvent
      geoconfirmed_event
    when InternetOutage
      internet_outage
    when TradeLocation
      trade_location
    when Flight
      flight
    when Ship
      ship
    when GpsJammingSnapshot
      gps_jamming_snapshot
    when Notam
      notam
    when CountryProfile
      country_profile
    when CountrySectorProfile
      country_sector_profile
    when SectorInputProfile
      sector_input_profile
    when CountryCommodityDependency
      country_commodity_dependency
    when CountryChokepointExposure
      country_chokepoint_exposure
    else
      fallback
    end
  end

  private

  attr_reader :evidence

  def news_story_cluster
    {
      type: "news_story_cluster",
      id: evidence.id,
      cluster_key: evidence.cluster_key,
      label: evidence.canonical_title,
      meta: [pluralize(evidence.source_count, "source"), pluralize(evidence.article_count, "article")].compact.join(" · "),
    }
  end

  def news_article
    {
      type: "news_article",
      id: evidence.id,
      label: evidence.title.presence || evidence.url,
      meta: evidence.publisher_name || evidence.origin_source_name,
      url: evidence.url,
    }
  end

  def commodity_price
    change = evidence.change_pct.present? ? "#{evidence.change_pct.to_f.positive? ? "+" : ""}#{evidence.change_pct}%" : nil
    {
      type: "commodity_price",
      id: evidence.id,
      symbol: evidence.symbol,
      label: evidence.name,
      meta: [evidence.symbol, change].compact.join(" · "),
    }
  end

  def earthquake
    {
      type: "earthquake",
      id: evidence.id,
      label: evidence.title.presence || earthquake_label,
      meta: [
        (evidence.magnitude.present? ? "M#{evidence.magnitude.to_f.round(1)}" : nil),
        (evidence.depth.present? ? "depth #{evidence.depth.to_f.round(1)}km" : nil),
        ("tsunami" if evidence.tsunami?),
        ("alert #{evidence.alert}" if evidence.alert.present?),
        evidence.event_time&.iso8601,
      ].compact.join(" · "),
    }
  end

  def fire_hotspot
    {
      type: "fire_hotspot",
      id: evidence.id,
      label: "Fire hotspot #{evidence.external_id}",
      meta: [
        evidence.confidence,
        (evidence.frp.present? ? "FRP #{evidence.frp.to_f.round(1)}" : nil),
        evidence.satellite,
        evidence.acq_datetime&.iso8601,
      ].compact.join(" · "),
    }
  end

  def natural_event
    {
      type: "natural_event",
      id: evidence.id,
      label: evidence.title.presence || evidence.category_title.presence || "Natural event",
      meta: [
        evidence.category_title,
        (evidence.magnitude_value.present? ? "#{evidence.magnitude_value.to_f.round(1)} #{evidence.magnitude_unit}".strip : nil),
        evidence.event_date&.iso8601,
      ].compact.join(" · "),
    }
  end

  def geoconfirmed_event
    {
      type: "geoconfirmed_event",
      id: evidence.id,
      label: evidence.title.presence || "GeoConfirmed event",
      meta: [
        evidence.map_region,
        evidence.posted_at&.iso8601 || evidence.event_time&.iso8601,
      ].compact.join(" · "),
    }
  end

  def internet_outage
    {
      type: "internet_outage",
      id: evidence.id,
      label: evidence.entity_name.presence || evidence.entity_code.presence || "Internet outage",
      meta: [
        evidence.entity_code,
        evidence.level,
        (evidence.score.present? ? "score #{evidence.score.to_f.round(1)}" : nil),
        evidence.started_at&.iso8601,
      ].compact.join(" · "),
    }
  end

  def trade_location
    {
      type: "trade_location",
      id: evidence.id,
      label: evidence.name,
      meta: [
        evidence.locode,
        evidence.location_kind,
        evidence.country_code,
      ].compact.join(" · "),
    }
  end

  def flight
    {
      type: "flight",
      id: evidence.id,
      label: evidence.callsign.presence || evidence.icao24.presence || "Tracked flight",
      meta: [
        evidence.military? ? "military" : "civilian",
        evidence.origin_country,
        evidence.aircraft_type,
      ].compact.join(" · "),
    }
  end

  def ship
    {
      type: "ship",
      id: evidence.id,
      label: evidence.name.presence || evidence.mmsi.presence || "Tracked ship",
      meta: [
        evidence.flag,
        evidence.destination,
        (evidence.speed.present? ? "#{evidence.speed.to_f.round(1)}kt" : nil),
      ].compact.join(" · "),
    }
  end

  def gps_jamming_snapshot
    {
      type: "gps_jamming_snapshot",
      id: evidence.id,
      label: "GPS jamming #{evidence.percentage.to_f.round(1)}%",
      meta: [evidence.level, evidence.recorded_at&.iso8601].compact.join(" · "),
    }
  end

  def notam
    {
      type: "notam",
      id: evidence.id,
      label: evidence.reason.presence || "Operational NOTAM",
      meta: [evidence.country, evidence.effective_start&.iso8601].compact.join(" · "),
    }
  end

  def country_profile
    {
      type: "country_profile",
      id: evidence.id,
      label: evidence.country_name,
      meta: [
        format_usd_short(evidence.gdp_nominal_usd, prefix: "GDP "),
        (evidence.latest_year if evidence.latest_year.present?),
      ].compact.join(" · "),
    }
  end

  def country_sector_profile
    {
      type: "country_sector_profile",
      id: evidence.id,
      label: "#{evidence.country_name} #{evidence.sector_name}",
      meta: [
        "#{evidence.share_pct.to_f.round(1)}% GDP share",
        ("rank #{evidence.rank}" if evidence.rank.present?),
      ].compact.join(" · "),
    }
  end

  def sector_input_profile
    {
      type: "sector_input_profile",
      id: evidence.id,
      label: evidence.input_name.presence || evidence.input_key.to_s.humanize,
      meta: [
        ("estimated" if evidence.metadata["estimated"]),
        evidence.input_kind,
        ("coeff #{evidence.coefficient.to_f.round(3)}" if evidence.coefficient.present?),
        evidence.scope_key,
      ].compact.join(" · "),
    }
  end

  def country_commodity_dependency
    {
      type: "country_commodity_dependency",
      id: evidence.id,
      label: "#{evidence.country_name} #{evidence.commodity_name.to_s.downcase} imports",
      meta: [
        ("estimated" if evidence.metadata["estimated"]),
        ("#{evidence.import_share_gdp_pct.to_f.round(2)}% GDP" if evidence.import_share_gdp_pct.present?),
        ("#{evidence.top_partner_country_name} #{evidence.top_partner_share_pct.to_f.round(1)}%" if evidence.top_partner_country_name.present? && evidence.top_partner_share_pct.present?),
      ].compact.join(" · "),
    }
  end

  def country_chokepoint_exposure
    {
      type: "country_chokepoint_exposure",
      id: evidence.id,
      label: "#{evidence.country_name} #{evidence.chokepoint_name} exposure",
      meta: [
        ("estimated" if evidence.metadata["estimated"]),
        evidence.commodity_name,
        ("score #{evidence.exposure_score.to_f.round(2)}" if evidence.exposure_score.present?),
      ].compact.join(" · "),
    }
  end

  def fallback
    {
      type: evidence.class.name.underscore,
      id: evidence.id,
      label: evidence.try(:canonical_name) || evidence.try(:canonical_title) || evidence.try(:title) || evidence.try(:name) || evidence.class.name,
    }
  end

  def earthquake_label
    return "M#{evidence.magnitude.to_f.round(1)} earthquake" if evidence.magnitude.present?

    "Earthquake"
  end

  def pluralize(count, noun)
    return if count.blank?

    "#{count} #{noun}#{count == 1 ? "" : "s"}"
  end

  def format_usd_short(value, prefix: "")
    return if value.blank?

    amount = value.to_f
    suffix = if amount >= 1_000_000_000_000
      "#{(amount / 1_000_000_000_000).round(2)}T"
    elsif amount >= 1_000_000_000
      "#{(amount / 1_000_000_000).round(1)}B"
    elsif amount >= 1_000_000
      "#{(amount / 1_000_000).round(1)}M"
    else
      amount.round.to_s
    end

    "#{prefix}$#{suffix}"
  end
end
