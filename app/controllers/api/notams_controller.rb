module Api
  class NotamsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      bounds = {
        lamin: params[:lamin]&.to_f || -90,
        lamax: params[:lamax]&.to_f || 90,
        lomin: params[:lomin]&.to_f || -180,
        lomax: params[:lomax]&.to_f || 180,
      }

      # Static no-fly zones
      zones = GLOBAL_NO_FLY_ZONES.select { |z| in_bounds?(z, bounds) }

      # Dynamic NOTAMs from DB (populated by NotamRefreshService)
      Notam.active.within_bounds(bounds).each do |n|
        zones << {
          id: n.external_id,
          lat: n.latitude,
          lng: n.longitude,
          radius_nm: n.radius_nm,
          radius_m: n.radius_m,
          alt_low_ft: n.alt_low_ft,
          alt_high_ft: n.alt_high_ft,
          reason: n.reason,
          text: n.text,
          country: n.country,
          effective_start: n.effective_start&.iso8601,
          effective_end: n.effective_end&.iso8601,
        }
      end

      expires_in 15.minutes, public: true
      render json: zones
    end

    private

    def in_bounds?(zone, bounds)
      zone[:lat] >= bounds[:lamin] && zone[:lat] <= bounds[:lamax] &&
        zone[:lng] >= bounds[:lomin] && zone[:lng] <= bounds[:lomax]
    end

    # rubocop:disable Metrics/MethodLength
    GLOBAL_NO_FLY_ZONES = [
      # ── Nuclear Facilities ──
      { id: "NFZ-NUC-001", lat: 51.3000, lng: 30.0030, radius_nm: 16, radius_m: 29_632, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Nuclear Facility", text: "Chernobyl Exclusion Zone, Ukraine - 30km permanent no-fly zone", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-002", lat: 37.4218, lng: 141.0337, radius_nm: 16, radius_m: 29_632, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Nuclear Facility", text: "Fukushima Daiichi Nuclear Power Plant, Japan", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-003", lat: 47.5119, lng: 34.5863, radius_nm: 16, radius_m: 29_632, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Nuclear Facility", text: "Zaporizhzhia Nuclear Power Plant, Ukraine", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-004", lat: 54.4200, lng: -3.5100, radius_nm: 2, radius_m: 3_704, alt_low_ft: 0, alt_high_ft: 2_000, reason: "Nuclear Facility", text: "Sellafield Nuclear Reprocessing Plant, UK", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-005", lat: 49.4528, lng: -1.8814, radius_nm: 2, radius_m: 3_704, alt_low_ft: 0, alt_high_ft: 2_000, reason: "Nuclear Facility", text: "La Hague Nuclear Reprocessing Plant, France", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-006", lat: 31.0013, lng: 35.1445, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Nuclear Facility", text: "Dimona Nuclear Research Center, Israel", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-007", lat: 33.7170, lng: 51.7170, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 30_000, reason: "Nuclear Facility", text: "Natanz Uranium Enrichment Facility, Iran", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-008", lat: 34.8856, lng: 50.9967, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 30_000, reason: "Nuclear Facility", text: "Fordow Underground Enrichment Facility, Iran", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-009", lat: 39.8000, lng: 125.7540, radius_nm: 10, radius_m: 18_520, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Nuclear Facility", text: "Yongbyon Nuclear Research Center, North Korea", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-010", lat: 33.6525, lng: 73.2580, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Nuclear Facility", text: "Khan Research Laboratories (Kahuta), Pakistan", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-011", lat: 19.0128, lng: 72.9237, radius_nm: 3, radius_m: 5_556, alt_low_ft: 0, alt_high_ft: 10_000, reason: "Nuclear Facility", text: "Bhabha Atomic Research Centre, Mumbai, India", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-012", lat: 35.3116, lng: -101.5597, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 18_000, reason: "Nuclear Facility", text: "Pantex Nuclear Weapons Plant, Texas, USA", effective_start: nil, effective_end: nil },
      { id: "NFZ-NUC-013", lat: 51.3254, lng: -1.3305, radius_nm: 2, radius_m: 3_704, alt_low_ft: 0, alt_high_ft: 2_000, reason: "Nuclear Facility", text: "AWE Aldermaston, Berkshire, UK", effective_start: nil, effective_end: nil },

      # ── Government / VIP ──
      { id: "NFZ-GOV-001", lat: 38.8977, lng: -77.0365, radius_nm: 15, radius_m: 27_780, alt_low_ft: 0, alt_high_ft: 18_000, reason: "Government", text: "Washington DC Flight Restricted Zone, USA", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-002", lat: 39.6483, lng: -77.4650, radius_nm: 3, radius_m: 5_556, alt_low_ft: 0, alt_high_ft: 18_000, reason: "Government", text: "Camp David Presidential Retreat, Maryland, USA", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-003", lat: 51.5014, lng: -0.1419, radius_nm: 1.5, radius_m: 2_778, alt_low_ft: 0, alt_high_ft: 2_500, reason: "Government", text: "Buckingham Palace and Central London, UK", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-004", lat: 48.8688, lng: 2.3098, radius_nm: 1.5, radius_m: 2_778, alt_low_ft: 0, alt_high_ft: 6_500, reason: "Government", text: "Elysee Palace, Paris, France", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-005", lat: 55.7520, lng: 37.6175, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 8_000, reason: "Government", text: "The Kremlin, Moscow, Russia", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-006", lat: 52.5186, lng: 13.3767, radius_nm: 1.5, radius_m: 2_778, alt_low_ft: 0, alt_high_ft: 3_000, reason: "Government", text: "Bundestag / Reichstag, Berlin, Germany", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-007", lat: 21.4225, lng: 39.8262, radius_nm: 12, radius_m: 22_224, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Government", text: "Mecca (Makkah), Saudi Arabia - permanent no-fly zone", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-008", lat: 31.7767, lng: 35.2345, radius_nm: 2, radius_m: 3_704, alt_low_ft: 0, alt_high_ft: 10_000, reason: "Government", text: "Temple Mount / Old City, Jerusalem, Israel", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-009", lat: 39.9163, lng: 116.3972, radius_nm: 10, radius_m: 18_520, alt_low_ft: 0, alt_high_ft: 15_000, reason: "Government", text: "Tiananmen Square / Zhongnanhai, Beijing, China", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-010", lat: 28.6139, lng: 77.2090, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 15_000, reason: "Government", text: "Parliament House, New Delhi, India", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-011", lat: 35.6762, lng: 51.4241, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 15_000, reason: "Government", text: "Government District, Tehran, Iran", effective_start: nil, effective_end: nil },
      { id: "NFZ-GOV-012", lat: 30.0444, lng: 31.2357, radius_nm: 3, radius_m: 5_556, alt_low_ft: 0, alt_high_ft: 10_000, reason: "Government", text: "Presidential Palace, Cairo, Egypt", effective_start: nil, effective_end: nil },

      # ── Military Bases ──
      { id: "NFZ-MIL-001", lat: 49.4397, lng: 7.6014, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 10_000, reason: "Military", text: "Ramstein Air Base, Germany - US/NATO", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-002", lat: 37.0012, lng: 35.4222, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Military", text: "Incirlik Air Base, Turkey - US/NATO", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-003", lat: -7.3133, lng: 72.4111, radius_nm: 30, radius_m: 55_560, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Military", text: "Diego Garcia, British Indian Ocean Territory", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-004", lat: -23.7990, lng: 133.7370, radius_nm: 2.5, radius_m: 4_630, alt_low_ft: 0, alt_high_ft: 18_000, reason: "Military", text: "Pine Gap Joint Defence Facility, Australia", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-005", lat: 37.2372, lng: -115.7993, radius_nm: 14, radius_m: 25_928, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Military", text: "Area 51 / Groom Lake, Nevada, USA", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-006", lat: -30.0000, lng: 134.0000, radius_nm: 100, radius_m: 185_200, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Military", text: "Woomera Prohibited Area, South Australia", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-007", lat: 36.2361, lng: -115.0344, radius_nm: 35, radius_m: 64_820, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Military", text: "Nellis Air Force Range, Nevada, USA", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-008", lat: 24.4539, lng: 54.6513, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Military", text: "Al Dhafra Air Base, Abu Dhabi, UAE", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-009", lat: 29.9695, lng: 47.7903, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Military", text: "Ali Al Salem Air Base, Kuwait", effective_start: nil, effective_end: nil },
      { id: "NFZ-MIL-010", lat: 35.4277, lng: 23.9518, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Military", text: "Souda Bay Naval Base, Crete, Greece - NATO", effective_start: nil, effective_end: nil },

      # ── Conflict Zones ──
      { id: "NFZ-CON-001", lat: 48.3794, lng: 31.1656, radius_nm: 300, radius_m: 555_600, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Conflict Zone", text: "Ukraine - entire airspace closed to civil aviation since Feb 2022", effective_start: nil, effective_end: nil },
      { id: "NFZ-CON-002", lat: 34.8021, lng: 38.9968, radius_nm: 200, radius_m: 370_400, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Conflict Zone", text: "Syria - Damascus FIR restricted airspace", effective_start: nil, effective_end: nil },
      { id: "NFZ-CON-003", lat: 26.8206, lng: 30.8025, radius_nm: 100, radius_m: 185_200, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Conflict Zone", text: "Libya - Tripoli FIR partially restricted", effective_start: nil, effective_end: nil },
      { id: "NFZ-CON-004", lat: 15.5527, lng: 48.5164, radius_nm: 100, radius_m: 185_200, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Conflict Zone", text: "Yemen - Sana'a FIR restricted airspace", effective_start: nil, effective_end: nil },
      { id: "NFZ-CON-005", lat: 33.3152, lng: 44.3661, radius_nm: 100, radius_m: 185_200, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Conflict Zone", text: "Iraq - Baghdad FIR partially restricted", effective_start: nil, effective_end: nil },
      { id: "NFZ-CON-006", lat: 2.0469, lng: 45.3182, radius_nm: 150, radius_m: 277_800, alt_low_ft: 0, alt_high_ft: 25_000, reason: "Conflict Zone", text: "Somalia - Mogadishu FIR restricted airspace", effective_start: nil, effective_end: nil },

      # ── DMZ / Security Zones ──
      { id: "NFZ-SEC-001", lat: 37.9536, lng: 126.6698, radius_nm: 100, radius_m: 185_200, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Security", text: "Korean DMZ No-Fly Zone", effective_start: nil, effective_end: nil },
      { id: "NFZ-SEC-002", lat: 40.0000, lng: 127.0000, radius_nm: 300, radius_m: 555_600, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Security", text: "North Korea - Pyongyang FIR, entire airspace restricted", effective_start: nil, effective_end: nil },
      { id: "NFZ-SEC-003", lat: 32.0853, lng: 34.7818, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 15_000, reason: "Security", text: "Tel Aviv / Ben Gurion Airport security zone, Israel", effective_start: nil, effective_end: nil },
      { id: "NFZ-SEC-004", lat: 28.3852, lng: -81.5639, radius_nm: 3, radius_m: 5_556, alt_low_ft: 0, alt_high_ft: 3_000, reason: "Security", text: "Walt Disney World TFR, Florida, USA", effective_start: nil, effective_end: nil },

      # ── Space Operations ──
      { id: "NFZ-SPC-001", lat: 45.9200, lng: 63.3420, radius_nm: 25, radius_m: 46_300, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "Baikonur Cosmodrome, Kazakhstan", effective_start: nil, effective_end: nil },
      { id: "NFZ-SPC-002", lat: 5.2360, lng: -52.7750, radius_nm: 15, radius_m: 27_780, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "Guiana Space Centre, Kourou, French Guiana - ESA", effective_start: nil, effective_end: nil },
      { id: "NFZ-SPC-003", lat: 40.9580, lng: 100.2910, radius_nm: 15, radius_m: 27_780, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "Jiuquan Satellite Launch Center, China", effective_start: nil, effective_end: nil },
      { id: "NFZ-SPC-004", lat: 13.7199, lng: 80.2304, radius_nm: 15, radius_m: 27_780, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "Satish Dhawan Space Centre, Sriharikota, India - ISRO", effective_start: nil, effective_end: nil },
      { id: "NFZ-SPC-005", lat: 28.5729, lng: -80.6490, radius_nm: 30, radius_m: 55_560, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "Kennedy Space Center / Cape Canaveral, Florida, USA", effective_start: nil, effective_end: nil },
      { id: "NFZ-SPC-006", lat: 34.7420, lng: -120.5724, radius_nm: 20, radius_m: 37_040, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "Vandenberg Space Force Base, California, USA", effective_start: nil, effective_end: nil },
      { id: "NFZ-SPC-007", lat: 19.6145, lng: 110.9510, radius_nm: 15, radius_m: 27_780, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "Wenchang Space Launch Site, Hainan, China", effective_start: nil, effective_end: nil },
      { id: "NFZ-SPC-008", lat: 62.9256, lng: 40.5779, radius_nm: 15, radius_m: 27_780, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "Plesetsk Cosmodrome, Russia", effective_start: nil, effective_end: nil },
      { id: "NFZ-SPC-009", lat: 25.9973, lng: -97.1571, radius_nm: 10, radius_m: 18_520, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Space Operations", text: "SpaceX Starbase, Boca Chica, Texas, USA", effective_start: nil, effective_end: nil },

      # ── Environmental ──
      { id: "NFZ-ENV-001", lat: -0.9538, lng: -90.9656, radius_nm: 40, radius_m: 74_080, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Environmental", text: "Galapagos Islands, Ecuador - restricted national park", effective_start: nil, effective_end: nil },
      { id: "NFZ-ENV-002", lat: -77.8500, lng: 166.6667, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 15_000, reason: "Environmental", text: "McMurdo Station, Antarctica", effective_start: nil, effective_end: nil },

      # ── Restricted Areas ──
      { id: "NFZ-RES-001", lat: 48.1044, lng: 11.6310, radius_nm: 1.5, radius_m: 2_778, alt_low_ft: 0, alt_high_ft: 3_000, reason: "Restricted Area", text: "ED-R Munich Government District, Germany", effective_start: nil, effective_end: nil },
      { id: "NFZ-RES-002", lat: 51.8985, lng: -5.2119, radius_nm: 10, radius_m: 18_520, alt_low_ft: 0, alt_high_ft: 50_000, reason: "Restricted Area", text: "Aberporth Military Range, West Wales, UK", effective_start: nil, effective_end: nil },
      { id: "NFZ-RES-003", lat: -5.8913, lng: -35.2592, radius_nm: 10, radius_m: 18_520, alt_low_ft: 0, alt_high_ft: 50_000, reason: "Restricted Area", text: "Barreira do Inferno Launch Center, Brazil", effective_start: nil, effective_end: nil },
      { id: "NFZ-RES-004", lat: -2.3104, lng: -44.3641, radius_nm: 15, radius_m: 27_780, alt_low_ft: 0, alt_high_ft: 99_999, reason: "Restricted Area", text: "Alcantara Launch Center, Brazil", effective_start: nil, effective_end: nil },
      { id: "NFZ-RES-005", lat: -15.7939, lng: -47.8828, radius_nm: 5, radius_m: 9_260, alt_low_ft: 0, alt_high_ft: 10_000, reason: "Restricted Area", text: "Government District, Brasilia, Brazil", effective_start: nil, effective_end: nil },
      { id: "NFZ-RES-006", lat: -34.6037, lng: -58.3816, radius_nm: 2, radius_m: 3_704, alt_low_ft: 0, alt_high_ft: 5_000, reason: "Restricted Area", text: "Casa Rosada, Buenos Aires, Argentina", effective_start: nil, effective_end: nil },
      { id: "NFZ-RES-007", lat: -1.2921, lng: 36.8219, radius_nm: 3, radius_m: 5_556, alt_low_ft: 0, alt_high_ft: 5_000, reason: "Restricted Area", text: "State House, Nairobi, Kenya", effective_start: nil, effective_end: nil },
    ].freeze
    # rubocop:enable Metrics/MethodLength
  end
end
