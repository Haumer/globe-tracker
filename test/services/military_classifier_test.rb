require "test_helper"

class MilitaryClassifierTest < ActiveSupport::TestCase
  test "military callsign prefix detected" do
    assert MilitaryClassifier.military?(icao24: "000000", callsign: "RCH123")
    assert MilitaryClassifier.military?(icao24: "000000", callsign: "FORTE12")
    assert MilitaryClassifier.military?(icao24: "000000", callsign: "NATO01")
  end

  test "military callsign pattern detected" do
    assert MilitaryClassifier.military?(icao24: "000000", callsign: "IFA3")
    assert MilitaryClassifier.military?(icao24: "000000", callsign: "RSAF5")
    assert MilitaryClassifier.military?(icao24: "000000", callsign: "TAF7")
  end

  test "civilian callsign prefix excludes from military" do
    assert_not MilitaryClassifier.military?(icao24: "4b8050", callsign: "PGT123")
    assert_not MilitaryClassifier.military?(icao24: "4b8050", callsign: "THY456")
    assert_not MilitaryClassifier.military?(icao24: "ae1234", callsign: "UAE789")
  end

  test "US military hex range detected" do
    assert MilitaryClassifier.military?(icao24: "ae1234", callsign: nil)
    assert MilitaryClassifier.military?(icao24: "afffff", callsign: nil)
  end

  test "UK military hex range detected" do
    assert MilitaryClassifier.military?(icao24: "43c500", callsign: nil)
  end

  test "non-military hex returns false" do
    assert_not MilitaryClassifier.military?(icao24: "a00000", callsign: nil)
    assert_not MilitaryClassifier.military?(icao24: "123456", callsign: nil)
  end

  test "country_for_hex returns correct country" do
    assert_equal "US", MilitaryClassifier.country_for_hex("ae5000")
    assert_equal "UK", MilitaryClassifier.country_for_hex("43c100")
    assert_equal "DE", MilitaryClassifier.country_for_hex("3f5000")
    assert_nil MilitaryClassifier.country_for_hex("123456")
    assert_nil MilitaryClassifier.country_for_hex(nil)
  end

  test "blank inputs return false" do
    assert_not MilitaryClassifier.military?(icao24: nil, callsign: nil)
    assert_not MilitaryClassifier.military?(icao24: "", callsign: "")
  end
end
