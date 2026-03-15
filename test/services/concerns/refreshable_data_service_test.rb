require "test_helper"

class RefreshableDataServiceTest < ActiveSupport::TestCase
  class FakeDataService
    include RefreshableDataService

    attr_accessor :data, :parsed, :upserted

    def fetch_data
      @data
    end

    def parse_records(data)
      @parsed = data
      data
    end

    def upsert_records(records)
      @upserted = records
    end
  end

  test "refresh returns 0 when fetch_data returns nil" do
    svc = FakeDataService.new
    svc.data = nil
    assert_equal 0, svc.refresh
  end

  test "refresh returns 0 when parse_records returns empty" do
    svc = FakeDataService.new
    svc.data = []
    assert_equal 0, svc.refresh
  end

  test "refresh calls upsert and returns record count" do
    svc = FakeDataService.new
    svc.data = [{ id: 1 }, { id: 2 }, { id: 3 }]
    assert_equal 3, svc.refresh
    assert_equal 3, svc.upserted.size
  end

  test "unique_key defaults to external_id" do
    svc = FakeDataService.new
    assert_equal :external_id, svc.send(:unique_key)
  end

  test "timeline_config defaults to nil" do
    svc = FakeDataService.new
    assert_nil svc.send(:timeline_config)
  end

  test "refresh rescues exceptions and returns 0" do
    svc = FakeDataService.new
    def svc.fetch_data; raise "boom"; end
    assert_equal 0, svc.refresh
  end
end
