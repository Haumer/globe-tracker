class AisStreamService
  extend SnapshotRecorder

  WS_URL = "wss://stream.aisstream.io/v0/stream"

  @running = false
  @thread = nil
  @buffer = []
  @buffer_mutex = Mutex.new

  class << self
    def start
      return if @running || ENV["AISSTREAM_API_KEY"].blank?

      @running = true
      @buffer = []
      @thread = Thread.new { run_stream }
      Rails.logger.info("AIS Stream: started")
    end

    def stop
      @running = false
      @thread&.kill
      @thread = nil
      Rails.logger.info("AIS Stream: stopped")
    end

    def running?
      @running
    end

    private

    def run_stream
      require "socket"
      require "openssl"
      require "websocket"

      while @running
        begin
          tcp = TCPSocket.new("stream.aisstream.io", 443)
          ssl_ctx = OpenSSL::SSL::SSLContext.new
          ssl = OpenSSL::SSL::SSLSocket.new(tcp, ssl_ctx)
          ssl.hostname = "stream.aisstream.io"
          ssl.connect

          handshake = WebSocket::Handshake::Client.new(url: WS_URL)
          ssl.write(handshake.to_s)

          buf = ""
          until handshake.finished?
            buf << ssl.readpartial(4096)
            handshake << buf
            buf = ""
          end

          unless handshake.valid?
            Rails.logger.error("AIS Stream: handshake failed")
            ssl.close rescue nil
            tcp.close rescue nil
            sleep 5
            next
          end

          # Subscribe
          subscribe = {
            APIKey: ENV["AISSTREAM_API_KEY"],
            BoundingBoxes: [[[-90, -180], [90, 180]]],
            FilterMessageTypes: ["PositionReport", "ShipStaticData"]
          }.to_json

          frame = WebSocket::Frame::Outgoing::Client.new(data: subscribe, type: :text, version: handshake.version)
          ssl.write(frame.to_s)
          Rails.logger.info("AIS Stream: connected and subscribed")

          parser = WebSocket::Frame::Incoming::Client.new(version: handshake.version)
          last_flush = Time.now.to_f

          # Blocking read loop — readpartial blocks until data arrives
          while @running
            chunk = ssl.readpartial(65536)
            parser << chunk

            while (msg = parser.next)
              next unless msg.type == :text || msg.type == :binary

              begin
                parsed = JSON.parse(msg.data)
                record = parse_message(parsed)
                @buffer_mutex.synchronize { @buffer << record } if record
              rescue JSON::ParserError
                # skip
              end
            end

            # Flush periodically
            now = Time.now.to_f
            if (now - last_flush) > 5 || @buffer.size >= 100
              to_flush = @buffer_mutex.synchronize { @buffer.dup.tap { @buffer.clear } }
              flush_buffer(to_flush)
              last_flush = now
            end
          end

          ssl.close rescue nil
          tcp.close rescue nil
        rescue EOFError, IOError, OpenSSL::SSL::SSLError, Errno::ECONNRESET => e
          Rails.logger.warn("AIS Stream: disconnected (#{e.message}), reconnecting...")
        rescue => e
          Rails.logger.error("AIS Stream error: #{e.class}: #{e.message}")
        ensure
          ssl&.close rescue nil
          tcp&.close rescue nil
        end

        sleep 5 if @running
      end
    end

    def parse_message(data)
      msg_type = data.dig("MessageType")
      meta = data.dig("MetaData")
      return nil unless meta

      mmsi = meta["MMSI"]&.to_s
      return nil if mmsi.blank?

      record = { mmsi: mmsi }
      record[:name] = meta["ShipName"]&.strip if meta["ShipName"].present?
      record[:latitude] = meta["latitude"] if meta["latitude"]
      record[:longitude] = meta["longitude"] if meta["longitude"]

      if msg_type == "PositionReport"
        pos = data.dig("Message", "PositionReport")
        if pos
          record[:speed] = pos["Sog"]
          record[:course] = pos["Cog"]
          record[:heading] = pos["TrueHeading"]
          record[:heading] = record[:course] if record[:heading] == 511
        end
      elsif msg_type == "ShipStaticData"
        static = data.dig("Message", "ShipStaticData")
        if static
          record[:ship_type] = static["Type"]
          record[:destination] = static["Destination"]&.strip
          record[:flag] = meta["country"]
        end
      end

      record
    end

    def flush_buffer(records)
      return if records.empty?

      all_keys = %i[mmsi name ship_type latitude longitude speed heading course destination flag]
      now = Time.current

      # Deduplicate by mmsi, keeping the last occurrence
      deduped = records.each_with_object({}) { |r, h| h[r[:mmsi]] = r }.values

      normalized = deduped.map do |r|
        row = {}
        all_keys.each { |k| row[k] = r[k] }
        row[:created_at] = now
        row[:updated_at] = now
        row
      end

      Ship.upsert_all(normalized, unique_by: :mmsi)
      record_ship_snapshots(normalized)
      Rails.logger.info("AIS Stream: flushed #{records.size} ships (total in DB: #{Ship.count})")
    rescue => e
      Rails.logger.error("AIS Stream flush error: #{e.message}")
    end
  end
end
