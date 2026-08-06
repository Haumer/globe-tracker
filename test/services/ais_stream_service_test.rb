require "test_helper"

class AisStreamServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
    OperationalOntologySyncService.instance_variable_set(:@recent_enqueue_slots, {})
    AisStreamService.instance_variable_set(:@running, false)
    AisStreamService.instance_variable_set(:@thread, nil)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    Rails.cache.clear
    OperationalOntologySyncService.instance_variable_set(:@recent_enqueue_slots, {})
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

  test "parse_message accepts the lowercase Metadata spelling too" do
    data = {
      "MessageType" => "PositionReport",
      "Metadata" => { "MMSI" => 222, "ShipName" => "DOC SPELLING", "latitude" => 1.0, "longitude" => 2.0 },
      "Message" => { "PositionReport" => { "Sog" => 3.0, "Cog" => 90.0, "TrueHeading" => 90 } }
    }

    result = AisStreamService.send(:parse_message, data)
    assert_equal "222", result[:mmsi]
    assert_equal "DOC SPELLING", result[:name]
  end

  # The stream looked identical whether it was idle or silently discarding
  # every message. Anything that does not become a record now gets counted.
  test "ingest_payload buffers records and reports what it could not parse" do
    AisStreamService.instance_variable_set(:@buffer, [])
    AisStreamService.instance_variable_set(:@unrecognised, 0)

    AisStreamService.send(:ingest_payload, {
      "MessageType" => "PositionReport",
      "MetaData" => { "MMSI" => 987, "latitude" => 1.0, "longitude" => 2.0 },
      "Message" => { "PositionReport" => { "Sog" => 1.0, "Cog" => 2.0, "TrueHeading" => 3 } }
    }.to_json)
    assert_equal 1, AisStreamService.instance_variable_get(:@buffer).size
    assert_equal 0, AisStreamService.instance_variable_get(:@unrecognised).to_i

    AisStreamService.send(:ingest_payload, { "error" => "invalid api key" }.to_json)
    AisStreamService.send(:ingest_payload, "this is not json")

    assert_equal 1, AisStreamService.instance_variable_get(:@buffer).size, "neither payload is a ship"
    assert_equal 2, AisStreamService.instance_variable_get(:@unrecognised).to_i
  end

  test "flush_buffer enqueues operational ontology sync" do
    records = [
      { mmsi: "123456789", name: "TEST VESSEL", latitude: 51.5, longitude: -0.1 }
    ]

    assert_enqueued_with(job: OperationalOntologyBatchJob) do
      AisStreamService.send(:flush_buffer, records)
    end

    ship = Ship.find_by!(mmsi: "123456789")
    assert_equal "TEST VESSEL", ship.name
  end
end
