class FireClusterService
  extend TimelineRecorder

  # A FIRMS row is one satellite thermal-anomaly detection -- a single pixel,
  # not a fire. A fire yields one row per pixel, per satellite, per pass, so the
  # raw feed reports ~102,000 "fires" a day for roughly 11,000 real ones, and a
  # large complex can appear 5,000 times over. This collapses detections into
  # fire complexes and scores each one's intensity.
  WINDOW = 24.hours

  # VIIRS pixels are 375m across. Snapping to ~2.2km merges the pixels of a
  # single fire without gluing genuinely separate fires together.
  CELL_DEGREES = 0.02

  # Two different satellites crossing the same fire minutes apart really is two
  # observations; the same satellite cannot re-observe within half an hour. So a
  # pass is identified by (half-hour bucket, platform).
  PASS_BUCKET_SECONDS = 1800

  # Forward-only 8-connectivity: each adjacent pair is still visited once, and
  # the reverse offsets would just repeat the same unions.
  NEIGHBOUR_OFFSETS = [[0, 1], [1, 0], [1, 1], [1, -1]].freeze

  # A real day produces ~25,000 clusters of 19 columns each. Postgres allows
  # 65,535 bind parameters per statement, so a single upsert_all would blow up
  # at roughly 3,400 rows.
  UPSERT_BATCH_SIZE = 1_000

  class << self
    def refresh(now: Time.current)
      detections = FireHotspot
        .where(acq_datetime: (now - WINDOW)..now)
        .where.not(latitude: nil).where.not(longitude: nil)
        .pluck(:latitude, :longitude, :frp, :acq_datetime, :satellite)

      persist!(build_clusters(detections, now: now))
    end

    # Exposed separately so the clustering can be exercised without a database.
    def build_clusters(detections, now: Time.current)
      cells = group_into_cells(detections)
      return [] if cells.empty?

      merge_adjacent(cells).map { |_root, cell_keys| summarise(cell_keys, cells, now: now) }
    end

    private

    def group_into_cells(detections)
      cells = Hash.new { |hash, key| hash[key] = [] }

      detections.each do |latitude, longitude, frp, acq_datetime, satellite|
        next if latitude.nil? || longitude.nil? || acq_datetime.nil?

        key = [(latitude / CELL_DEGREES).floor, (longitude / CELL_DEGREES).floor]
        cells[key] << [latitude.to_f, longitude.to_f, frp.to_f, acq_datetime, satellite]
      end

      cells
    end

    # Union-find over occupied cells, so a fire straddling a cell boundary stays
    # one fire. Grid-only grouping would split it, which is how the biggest
    # complexes were being reported as several unrelated hotspots.
    def merge_adjacent(cells)
      parent = {}
      cells.each_key { |cell| parent[cell] = cell }

      find = lambda do |cell|
        root = cell
        root = parent[root] while parent[root] != root
        while parent[cell] != root
          parent[cell], cell = root, parent[cell]
        end
        root
      end

      union = lambda do |a, b|
        root_a = find.call(a)
        root_b = find.call(b)
        parent[root_a] = root_b unless root_a == root_b
      end

      cells.each_key do |(i, j)|
        NEIGHBOUR_OFFSETS.each do |di, dj|
          neighbour = [i + di, j + dj]
          union.call([i, j], neighbour) if cells.key?(neighbour)
        end
      end

      groups = Hash.new { |hash, key| hash[key] = [] }
      cells.each_key { |cell| groups[find.call(cell)] << cell }
      groups
    end

    def summarise(cell_keys, cells, now:)
      detections = cell_keys.flat_map { |cell| cells[cell] }

      # Intensity is the strongest SINGLE pass, never the sum across passes --
      # summing every detection reports a fire seen 15 times at 15x its real
      # output, and inflates the global total 2.6x.
      passes = detections.group_by { |_, _, _, acq_datetime, satellite|
        [acq_datetime.to_i / PASS_BUCKET_SECONDS, satellite]
      }
      pass_totals = passes.transform_values { |rows| rows.sum { |_, _, frp, _, _| frp } }
      latest_pass = passes.keys.max_by { |bucket, _| bucket }

      intensity = pass_totals.values.max.to_f
      times = detections.map { |_, _, _, acq_datetime, _| acq_datetime }
      latitudes = detections.map(&:first)
      longitudes = detections.map { |_, longitude, _, _, _| longitude }
      centre = weighted_centre(detections)
      external_id = external_id_for(cell_keys)

      {
        external_id: external_id,
        observations: observations_for(external_id, passes),
        latitude: centre[0],
        longitude: centre[1],
        intensity_mw: intensity,
        latest_mw: pass_totals[latest_pass].to_f,
        tier: FireCluster.tier_for(intensity),
        pixel_count: detections.map { |latitude, longitude, _, _, _| [latitude, longitude] }.uniq.size,
        pass_count: passes.size,
        detection_count: detections.size,
        first_detected_at: times.min,
        last_detected_at: times.max,
        satellites: detections.map { |_, _, _, _, satellite| satellite }.compact.uniq.sort,
        min_latitude: latitudes.min,
        max_latitude: latitudes.max,
        min_longitude: longitudes.min,
        max_longitude: longitudes.max,
        computed_at: now,
      }
    end

    # One row per satellite pass. This is the evidence behind the cluster and
    # the series that shows the fire growing or dying -- the aggregate alone
    # cannot express either, since it only keeps peak and latest.
    def observations_for(cluster_external_id, passes)
      passes.map do |(bucket, satellite), rows|
        centre = weighted_centre(rows)

        {
          external_id: "#{cluster_external_id}:#{bucket}:#{satellite}",
          satellite: satellite,
          instrument: instrument_for(satellite),
          acq_datetime: rows.map { |_, _, _, acq_datetime, _| acq_datetime }.min,
          frp_mw: rows.sum { |_, _, frp, _, _| frp },
          pixel_count: rows.map { |latitude, longitude, _, _, _| [latitude, longitude] }.uniq.size,
          latitude: centre[0],
          longitude: centre[1],
        }
      end
    end

    # MODIS resolves 1km pixels and VIIRS 375m, so the two report very different
    # pixel counts and radiances for the same fire. Recording which instrument
    # saw a pass is what stops a graph comparing them as if they were alike.
    MODIS_PLATFORMS = ["Terra", "Aqua"].freeze

    def instrument_for(satellite)
      MODIS_PLATFORMS.include?(satellite) ? "MODIS" : "VIIRS"
    end

    # Bright pixels pull the marker toward the burning front rather than the
    # geometric middle of the footprint, which for a long fire front is empty ground.
    def weighted_centre(detections)
      total = detections.sum { |_, _, frp, _, _| frp }
      return [mean(detections.map(&:first)), mean(detections.map { |_, lng, _, _, _| lng })] if total <= 0

      [
        detections.sum { |latitude, _, frp, _, _| latitude * frp } / total,
        detections.sum { |_, longitude, frp, _, _| longitude * frp } / total,
      ]
    end

    def mean(values)
      values.sum / values.size.to_f
    end

    # Derived from the cluster's lowest cell so the same footprint always yields
    # the same id. Identity is best-effort: a fire that grows past a new lowest
    # cell is issued a new id, which is why nothing downstream should treat this
    # as a durable key for anything but a single render.
    def external_id_for(cell_keys)
      i, j = cell_keys.min
      "fc_#{i}_#{j}"
    end

    def persist!(clusters)
      if clusters.empty?
        FireCluster.delete_all
        return 0
      end

      rows = clusters.map { |cluster| cluster.except(:observations) }
      rows.each_slice(UPSERT_BATCH_SIZE) do |batch|
        FireCluster.upsert_all(batch, unique_by: :external_id, record_timestamps: true)
      end

      # Clusters whose fires stopped being detected have to go, or the map keeps
      # showing extinguished fires indefinitely. Observations cascade with them.
      live_ids = clusters.map { |cluster| cluster[:external_id] }
      FireCluster.where.not(external_id: live_ids).delete_all

      persist_observations!(clusters)

      # One timeline event per fire complex, replacing one per satellite pixel.
      record_timeline_events(
        event_type: "fire",
        model_class: FireCluster,
        unique_key: :external_id,
        unique_values: live_ids,
        time_column: :last_detected_at
      )

      clusters.size
    end

    def persist_observations!(clusters)
      cluster_ids = FireCluster.where(external_id: clusters.map { |c| c[:external_id] })
                               .pluck(:external_id, :id).to_h

      rows = clusters.flat_map do |cluster|
        cluster_id = cluster_ids[cluster[:external_id]]
        next [] unless cluster_id

        cluster[:observations].map { |observation| observation.merge(fire_cluster_id: cluster_id) }
      end
      return if rows.empty?

      rows.each_slice(UPSERT_BATCH_SIZE) do |batch|
        FireObservation.upsert_all(batch, unique_by: :external_id, record_timestamps: true)
      end

      # A pass that aged out of the window must not linger in the series.
      FireObservation.where(fire_cluster_id: cluster_ids.values)
                     .where.not(external_id: rows.map { |row| row[:external_id] })
                     .delete_all
    end
  end
end
