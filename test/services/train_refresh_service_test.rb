require "test_helper"

class TrainRefreshServiceTest < ActiveSupport::TestCase
  test "refresh persists ingests and observations from snapshots" do
    fetched_at = Time.current

    snapshots = [
      {
        operator_key: "oebb",
        operator_name: "ÖBB",
        operator_flag: "AT",
        request_bbox: nil,
        request_rect: { llCrd: { x: 9_500_000, y: 46_500_000 }, urCrd: { x: 17_100_000, y: 49_000_000 } },
        fetched_at: fetched_at,
        raw_payload: { "svcResL" => [] },
        status: "fetched",
        error_code: nil,
        trains: [
          {
            id: "oebb-ice-123",
            name: "ICE 123",
            category: "ICE",
            categoryLong: "InterCityExpress",
            operator: "ÖBB",
            flag: "AT",
            lat: 48.21,
            lng: 16.37,
            direction: "Wien",
            progress: 42,
          },
        ],
      },
    ]

    with_stubbed_train_snapshots(snapshots) do
      assert_difference("TrainIngest.count", 1) do
        assert_difference("TrainObservation.count", 1) do
          assert_equal 1, TrainRefreshService.refresh
        end
      end
    end

    observation = TrainObservation.find_by!(external_id: "oebb-ice-123")
    assert_equal "ÖBB", observation.operator_name
    assert_equal "ICE", observation.category
    assert_equal 42, observation.progress
  end

  test "refresh deletes missing observations for a successful operator snapshot" do
    stale_ingest = TrainIngest.create!(
      source_key: "oebb",
      source_name: "ÖBB",
      status: "fetched",
      request_metadata: {},
      raw_payload: {},
      fetched_at: 2.minutes.ago,
    )

    TrainObservation.create!(
      external_id: "old-train",
      train_ingest: stale_ingest,
      source: "hafas",
      operator_key: "oebb",
      operator_name: "ÖBB",
      name: "Old Train",
      category: "RE",
      category_long: "Regional",
      latitude: 48.2,
      longitude: 16.3,
      raw_payload: {},
      fetched_at: 2.minutes.ago,
      expires_at: 30.seconds.from_now,
    )

    snapshots = [
      {
        operator_key: "oebb",
        operator_name: "ÖBB",
        operator_flag: "AT",
        request_bbox: nil,
        request_rect: {},
        fetched_at: Time.current,
        raw_payload: {},
        status: "fetched",
        error_code: nil,
        trains: [],
      },
    ]

    with_stubbed_train_snapshots(snapshots) do
      assert_equal 0, TrainRefreshService.refresh
    end

    assert_nil TrainObservation.find_by(external_id: "old-train")
  end

  test "refresh_if_stale delegates to the class refresh implementation" do
    snapshots = [
      {
        operator_key: "oebb",
        operator_name: "ÖBB",
        operator_flag: "AT",
        request_bbox: nil,
        request_rect: {},
        fetched_at: Time.current,
        raw_payload: {},
        status: "fetched",
        error_code: nil,
        trains: [
          {
            id: "oebb-rjx-42",
            name: "RJX 42",
            category: "RJX",
            categoryLong: "Railjet Express",
            operator: "ÖBB",
            flag: "AT",
            lat: 48.2,
            lng: 16.36,
            direction: "Wien",
            progress: 10,
          },
        ],
      },
    ]

    with_stubbed_train_snapshots(snapshots) do
      assert_difference("TrainObservation.count", 1) do
        assert_equal 1, TrainRefreshService.refresh_if_stale(force: true)
      end
    end
  end

  private

  def with_stubbed_train_snapshots(result)
    original = HafasTrainService.method(:fetch_snapshots)
    HafasTrainService.define_singleton_method(:fetch_snapshots) { |**_args| result }
    yield
  ensure
    HafasTrainService.define_singleton_method(:fetch_snapshots, original)
  end
end
