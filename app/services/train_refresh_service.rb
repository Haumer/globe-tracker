class TrainRefreshService
  extend Refreshable

  EXPIRY_WINDOW = 90.seconds

  refreshes model: TrainObservation, interval: 1.minute

  class << self
    def refresh
      snapshots = HafasTrainService.fetch_snapshots
      return 0 if snapshots.blank?

      total = 0

      snapshots.each do |snapshot|
        ingest = TrainIngest.create!(
          source_key: snapshot[:operator_key],
          source_name: snapshot[:operator_name],
          status: snapshot[:status],
          error_code: snapshot[:error_code],
          request_metadata: {
            bbox: snapshot[:request_bbox],
            rect: snapshot[:request_rect],
          },
          raw_payload: snapshot[:raw_payload] || {},
          fetched_at: snapshot[:fetched_at],
        )

        next unless snapshot[:status] == "fetched"

        records = build_records(snapshot, ingest.id)
        cleanup_missing_records(snapshot[:operator_key], records.map { |record| record[:external_id] })
        if records.any?
          TrainObservation.upsert_all(records, unique_by: :external_id)
        end
        total += records.size
      end

      purge_stale_records
      total
    rescue StandardError => e
      Rails.logger.error("TrainRefreshService: #{e.message}")
      0
    end

    private

    def build_records(snapshot, ingest_id)
      now = Time.current

      snapshot[:trains].filter_map do |train|
        next if train[:lat].blank? || train[:lng].blank?

        {
          external_id: train[:id],
          train_ingest_id: ingest_id,
          source: "hafas",
          operator_key: snapshot[:operator_key],
          operator_name: train[:operator].presence || snapshot[:operator_name],
          name: train[:name],
          category: train[:category],
          category_long: train[:categoryLong],
          flag: train[:flag].presence || snapshot[:operator_flag],
          latitude: train[:lat],
          longitude: train[:lng],
          direction: train[:direction],
          progress: normalize_progress(train[:progress]),
          raw_payload: train.as_json,
          fetched_at: snapshot[:fetched_at],
          expires_at: snapshot[:fetched_at] + EXPIRY_WINDOW,
          created_at: now,
          updated_at: now,
        }
      end
    end

    def cleanup_missing_records(operator_key, seen_ids)
      scope = TrainObservation.where(operator_key: operator_key)
      scope = scope.where.not(external_id: seen_ids) if seen_ids.any?
      scope.delete_all
    end

    def purge_stale_records
      TrainObservation.where("expires_at < ?", 5.minutes.ago).delete_all
    end

    def normalize_progress(value)
      return nil if value.nil?

      value.to_i
    rescue StandardError
      nil
    end
  end
end
