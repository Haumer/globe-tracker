class ClassifiedSatelliteEnrichmentService
  # Enriches analyst/classified satellites using orbital mechanics analysis.
  # Since these objects have no official COSPAR ID, SATCAT record, or UCS entry,
  # we derive mission type and likely operator from TLE orbital parameters.

  # Known classified programs matched by orbital signature
  # Format: { test: ->(inc, alt, ecc, period) -> bool, name:, operator:, mission:, detail: }
  ORBITAL_SIGNATURES = [
    # US NRO KH-11 type optical reconnaissance — SSO ~250-400 km, 97-98°
    {
      name: "KH-11 Keyhole-class",
      test: ->(inc, alt, ecc, _p) { inc.between?(96.5, 98.5) && alt.between?(200, 450) && ecc < 0.01 },
      operator: "US NRO (probable)",
      mission: "imaging",
      detail: "Optical reconnaissance — low SSO consistent with KH-11 Keyhole/Crystal",
    },
    # US NRO Lacrosse/Onyx SAR — ~57° or ~68° inclination, 400-700 km
    {
      name: "Lacrosse/Onyx-class",
      test: ->(inc, alt, ecc, _p) { (inc.between?(56, 59) || inc.between?(67, 69)) && alt.between?(400, 750) && ecc < 0.02 },
      operator: "US NRO (probable)",
      mission: "radar_imaging",
      detail: "Synthetic Aperture Radar — orbit consistent with Lacrosse/Topaz",
    },
    # US NRO Mentor/Orion SIGINT — near-GEO, inclined
    {
      name: "Mentor/Orion-class",
      test: ->(inc, alt, ecc, _p) { alt.between?(35000, 37000) && inc > 2 },
      operator: "US NRO (probable)",
      mission: "sigint",
      detail: "Geostationary SIGINT — large antenna, consistent with Mentor/Orion",
    },
    # US SBIRS/DSP early warning — GEO, low inclination
    {
      name: "Early warning (GEO)",
      test: ->(inc, alt, ecc, _p) { alt.between?(35000, 37000) && inc < 2 },
      operator: "US DoD (probable)",
      mission: "early_warning",
      detail: "Geostationary early warning / missile detection",
    },
    # Russian Liana/Pion SIGINT — ~67° inclination, 700-1000 km
    {
      name: "Liana/Pion-class",
      test: ->(inc, alt, ecc, _p) { inc.between?(66, 68) && alt.between?(700, 1100) && ecc < 0.01 },
      operator: "Russia MoD (probable)",
      mission: "sigint",
      detail: "Naval SIGINT/ELINT — orbit consistent with Liana/Pion-NKS",
    },
    # Russian Bars-M optical reconnaissance — SSO ~97.6°, ~550-590 km
    {
      name: "Bars-M class",
      test: ->(inc, alt, ecc, _p) { inc.between?(97.2, 98.0) && alt.between?(530, 610) && ecc < 0.005 },
      operator: "Russia MoD (probable)",
      mission: "imaging",
      detail: "Optical mapping/reconnaissance — orbit consistent with Bars-M",
    },
    # Molniya-type HEO — ~63° inclination, high eccentricity (Russian early warning or SIGINT)
    {
      name: "Molniya-type HEO",
      test: ->(inc, _alt, ecc, _p) { inc.between?(62, 66) && ecc > 0.2 },
      operator: "Russia MoD (probable)",
      mission: "sigint",
      detail: "Highly elliptical Molniya orbit — likely SIGINT or early warning relay",
    },
    # Chinese Yaogan series — ~63° inclination, ~500-700 km triplets
    {
      name: "Yaogan-class",
      test: ->(inc, alt, ecc, _p) { inc.between?(62, 64) && alt.between?(480, 720) && ecc < 0.02 },
      operator: "China PLA (probable)",
      mission: "reconnaissance",
      detail: "Orbit consistent with Yaogan electronic/optical reconnaissance triplets",
    },
    # SSO radar/SAR imaging — ~97-103°, 800-1200 km
    {
      name: "SAR/Radar imaging (SSO)",
      test: ->(inc, alt, ecc, _p) { inc.between?(96, 103) && alt.between?(800, 1300) && ecc < 0.03 },
      operator: "Unknown state",
      mission: "radar_imaging",
      detail: "Sun-synchronous radar/SAR imaging — altitude suited for synthetic aperture radar",
    },
    # SSO optical imaging — ~96-100°, 200-800 km
    {
      name: "Optical imaging (SSO)",
      test: ->(inc, alt, ecc, _p) { inc.between?(96, 100) && alt.between?(200, 800) && ecc < 0.02 },
      operator: "Unknown state",
      mission: "imaging",
      detail: "Sun-synchronous optical imaging — standard reconnaissance orbit",
    },
    # Polar ELINT — ~90° inclination, 1000-1500 km
    {
      name: "Polar ELINT",
      test: ->(inc, alt, ecc, _p) { inc.between?(88, 92) && alt.between?(1000, 1500) && ecc < 0.01 },
      operator: "Unknown state",
      mission: "sigint",
      detail: "Polar orbit ELINT — full global coverage signals intelligence",
    },
    # Non-Molniya eccentric MEO — ~54-84° inclination, MEO with moderate eccentricity
    {
      name: "Eccentric MEO surveillance",
      test: ->(inc, alt, ecc, _p) { inc.between?(50, 85) && alt.between?(2000, 5000) && ecc > 0.1 },
      operator: "Unknown state",
      mission: "sigint",
      detail: "Eccentric MEO orbit — likely SIGINT with extended dwell time over target regions",
    },
    # Mid-inclination LEO SIGINT — 60-85°, varied altitudes, may have moderate eccentricity
    {
      name: "SIGINT/ELINT (LEO)",
      test: ->(inc, alt, ecc, _p) { inc.between?(60, 86) && alt.between?(400, 2100) && ecc < 0.1 },
      operator: "Unknown state",
      mission: "sigint",
      detail: "LEO signals intelligence — mid-inclination electronic surveillance",
    },
    # Near-polar LEO — ~85-88°, 400-600 km
    {
      name: "Near-polar imaging",
      test: ->(inc, alt, ecc, _p) { inc.between?(85, 88) && alt.between?(400, 700) && ecc < 0.01 },
      operator: "Unknown state",
      mission: "imaging",
      detail: "Near-polar orbit — likely optical reconnaissance with global coverage",
    },
    # High LEO — could be navigation augmentation or ELINT
    {
      name: "Navigation/ELINT",
      test: ->(inc, alt, ecc, _p) { alt.between?(1000, 2000) && ecc < 0.1 },
      operator: "Unknown state",
      mission: "sigint",
      detail: "High LEO — possible ELINT or navigation augmentation",
    },
    # Catch-all for remaining LEO
    {
      name: "LEO surveillance (unclassified type)",
      test: ->(inc, alt, ecc, _p) { alt.between?(200, 2000) },
      operator: "Unknown state",
      mission: "reconnaissance",
      detail: "Low Earth orbit — mission type could not be determined from orbital parameters",
    },
    # Catch-all for MEO/HEO
    {
      name: "MEO/HEO (unclassified type)",
      test: ->(inc, alt, ecc, _p) { alt > 2000 },
      operator: "Unknown state",
      mission: "sigint",
      detail: "Medium/high orbit — likely signals intelligence or communications relay",
    },
  ].freeze

  MISSION_LABELS = {
    "imaging" => "Reconnaissance (Optical)",
    "radar_imaging" => "Reconnaissance (Radar/SAR)",
    "sigint" => "Signals Intelligence (SIGINT/ELINT)",
    "early_warning" => "Early Warning / Missile Defense",
    "reconnaissance" => "Reconnaissance (Multi-sensor)",
  }.freeze

  class << self
    def enrich_all
      satellites = Satellite.where(category: "analyst")
      enriched = 0

      satellites.find_each do |sat|
        params = extract_orbital_params(sat.tle_line2)
        next unless params

        signature = match_signature(params)
        next unless signature

        attrs = {
          operator: signature[:operator],
          mission_type: signature[:mission],
          purpose: MISSION_LABELS[signature[:mission]] || signature[:mission],
          detailed_purpose: signature[:detail],
          orbit_class: classify_orbit(params[:alt_km], params[:inclination], params[:eccentricity]),
        }

        # Only update if something changed
        changed = attrs.any? { |k, v| sat.send(k) != v }
        if changed
          sat.update_columns(attrs.merge(updated_at: Time.current))
          enriched += 1
        end
      end

      # Group co-orbital objects (launched together)
      group_co_orbitals

      Rails.logger.info("Classified enrichment: updated #{enriched} of #{satellites.count} analyst satellites")
      enriched
    end

    private

    def extract_orbital_params(tle_line2)
      return nil if tle_line2.blank? || tle_line2.length < 69

      inclination = tle_line2[8..15].strip.to_f
      eccentricity = ("0." + tle_line2[26..32].strip).to_f
      mean_motion = tle_line2[52..62].strip.to_f
      return nil if mean_motion == 0

      period_min = 1440.0 / mean_motion
      semi_major_axis = (398600.4418 * (period_min * 60)**2 / (4 * Math::PI**2))**(1.0 / 3)
      alt_km = semi_major_axis - 6371

      {
        inclination: inclination,
        eccentricity: eccentricity,
        mean_motion: mean_motion,
        period_min: period_min,
        alt_km: alt_km,
      }
    end

    def match_signature(params)
      ORBITAL_SIGNATURES.each do |sig|
        if sig[:test].call(params[:inclination], params[:alt_km], params[:eccentricity], params[:period_min])
          return sig
        end
      end
      nil
    end

    def classify_orbit(alt_km, inclination, eccentricity)
      if eccentricity > 0.2
        "HEO (Highly Elliptical)"
      elsif alt_km.between?(35000, 37000)
        inclination < 5 ? "GEO (Geostationary)" : "GEO (Inclined)"
      elsif alt_km.between?(2000, 35000)
        "MEO (Medium Earth)"
      elsif inclination.between?(96, 103)
        "SSO (Sun-Synchronous)"
      elsif inclination > 85
        "Polar LEO"
      else
        "LEO (Low Earth)"
      end
    end

    def group_co_orbitals
      # Find satellites in very similar orbits (likely launched together)
      analysts = Satellite.where(category: "analyst").pluck(:id, :norad_id, :tle_line2)
      return if analysts.empty?

      orbital_data = analysts.filter_map do |id, norad_id, tle2|
        params = extract_orbital_params(tle2)
        next unless params
        [id, norad_id, params]
      end

      # Group by similar orbital parameters (within tolerances)
      groups = []
      used = Set.new

      orbital_data.each do |id, norad_id, params|
        next if used.include?(id)

        group = [[id, norad_id, params]]
        used << id

        orbital_data.each do |id2, norad_id2, params2|
          next if used.include?(id2)
          next unless orbits_similar?(params, params2)

          group << [id2, norad_id2, params2]
          used << id2
        end

        groups << group if group.size > 1
      end

      # Update satellites in groups with constellation info
      groups.each_with_index do |group, idx|
        norad_ids = group.map { |_, nid, _| nid }.sort
        group_label = "Constellation #{norad_ids.first}-#{norad_ids.last} (#{group.size} objects)"

        ids = group.map { |id, _, _| id }
        Satellite.where(id: ids).where(contractor: [nil, ""]).update_all(contractor: group_label)
      end

      Rails.logger.info("Classified enrichment: found #{groups.size} co-orbital groups")
    end

    def orbits_similar?(a, b)
      (a[:inclination] - b[:inclination]).abs < 0.5 &&
        (a[:alt_km] - b[:alt_km]).abs < 30 &&
        (a[:eccentricity] - b[:eccentricity]).abs < 0.005
    end
  end
end
