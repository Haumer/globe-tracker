require "test_helper"

class ClassifiedSatelliteEnrichmentServiceTest < ActiveSupport::TestCase
  test "extract_orbital_params returns nil for blank TLE" do
    assert_nil ClassifiedSatelliteEnrichmentService.send(:extract_orbital_params, nil)
    assert_nil ClassifiedSatelliteEnrichmentService.send(:extract_orbital_params, "")
    assert_nil ClassifiedSatelliteEnrichmentService.send(:extract_orbital_params, "short")
  end

  test "extract_orbital_params parses valid TLE line 2" do
    # ISS-like TLE line 2: inc=51.64, ecc=0.0005, mean_motion=15.5
    tle2 = "2 25544  51.6400 200.0000 0005000 100.0000 260.0000 15.50000000400000"
    params = ClassifiedSatelliteEnrichmentService.send(:extract_orbital_params, tle2)

    assert_in_delta 51.64, params[:inclination], 0.01
    assert_in_delta 0.0005, params[:eccentricity], 0.0001
    assert_in_delta 15.5, params[:mean_motion], 0.01
    assert params[:alt_km] > 200 && params[:alt_km] < 500
  end

  test "classify_orbit returns correct classifications" do
    assert_equal "GEO (Geostationary)", ClassifiedSatelliteEnrichmentService.send(:classify_orbit, 36000, 1.0, 0.001)
    assert_equal "GEO (Inclined)", ClassifiedSatelliteEnrichmentService.send(:classify_orbit, 36000, 10.0, 0.001)
    assert_equal "HEO (Highly Elliptical)", ClassifiedSatelliteEnrichmentService.send(:classify_orbit, 20000, 63.0, 0.5)
    assert_equal "SSO (Sun-Synchronous)", ClassifiedSatelliteEnrichmentService.send(:classify_orbit, 500, 98.0, 0.001)
    assert_equal "LEO (Low Earth)", ClassifiedSatelliteEnrichmentService.send(:classify_orbit, 400, 51.6, 0.001)
    assert_equal "MEO (Medium Earth)", ClassifiedSatelliteEnrichmentService.send(:classify_orbit, 20000, 55.0, 0.01)
    assert_equal "Polar LEO", ClassifiedSatelliteEnrichmentService.send(:classify_orbit, 500, 87.0, 0.001)
  end

  test "match_signature finds KH-11 for low SSO orbit" do
    params = { inclination: 97.5, alt_km: 300, eccentricity: 0.005, period_min: 90 }
    sig = ClassifiedSatelliteEnrichmentService.send(:match_signature, params)
    assert_equal "KH-11 Keyhole-class", sig[:name]
    assert_equal "imaging", sig[:mission]
  end

  test "orbits_similar? detects close orbits" do
    a = { inclination: 97.5, alt_km: 400, eccentricity: 0.001 }
    b = { inclination: 97.6, alt_km: 410, eccentricity: 0.002 }
    assert ClassifiedSatelliteEnrichmentService.send(:orbits_similar?, a, b)
  end

  test "orbits_similar? rejects distant orbits" do
    a = { inclination: 97.5, alt_km: 400, eccentricity: 0.001 }
    b = { inclination: 55.0, alt_km: 800, eccentricity: 0.1 }
    assert_not ClassifiedSatelliteEnrichmentService.send(:orbits_similar?, a, b)
  end

  test "MISSION_LABELS covers expected mission types" do
    assert_equal "Reconnaissance (Optical)", ClassifiedSatelliteEnrichmentService::MISSION_LABELS["imaging"]
    assert_equal "Signals Intelligence (SIGINT/ELINT)", ClassifiedSatelliteEnrichmentService::MISSION_LABELS["sigint"]
  end
end
