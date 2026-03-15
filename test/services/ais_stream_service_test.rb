require "test_helper"

class AisStreamServiceTest < ActiveSupport::TestCase
  setup do
    AisStreamService.instance_variable_set(:@running, false)
    AisStreamService.instance_variable_set(:@thread, nil)
  end

  test "running? returns false by default" do
    assert_not AisStreamService.running?
  end

  test "start does nothing when AISSTREAM_API_KEY is blank" do
    original = ENV["AISSTREAM_API_KEY"]
    begin
      ENV["AISSTREAM_API_KEY"] = nil
      AisStreamService.start
      assert_not AisStreamService.running?
    ensure
      ENV["AISSTREAM_API_KEY"] = original
    end
  end

  test "stop sets running to false" do
    AisStreamService.instance_variable_set(:@running, true)
    AisStreamService.stop
    assert_not AisStreamService.running?
  end

  test "parse_message extracts position report fields" do
    data = {
      "MessageType" => "PositionReport",
      "MetaData" => { "MMSI" => 123456789, "ShipName" => "TEST VESSEL", "latitude" => 51.5, "longitude" => -0.1 },
      "Message" => { "PositionReport" => { "Sog" => 12.5, "Cog" => 180.0, "TrueHeading" => 179 } }
    }

    result = AisStreamService.send(:parse_message, data)
    assert_equal "123456789", result[:mmsi]
    assert_equal "TEST VESSEL", result[:name]
    assert_equal 51.5, result[:latitude]
    assert_equal 12.5, result[:speed]
    assert_equal 179, result[:heading]
  end

  test "parse_message returns nil without MetaData" do
    result = AisStreamService.send(:parse_message, { "MessageType" => "PositionReport" })
    assert_nil result
  end

  test "parse_message replaces heading 511 with course" do
    data = {
      "MessageType" => "PositionReport",
      "MetaData" => { "MMSI" => 111, "latitude" => 0, "longitude" => 0 },
      "Message" => { "PositionReport" => { "Sog" => 5, "Cog" => 90.0, "TrueHeading" => 511 } }
    }

    result = AisStreamService.send(:parse_message, data)
    assert_equal 90.0, result[:heading]
  end
end
