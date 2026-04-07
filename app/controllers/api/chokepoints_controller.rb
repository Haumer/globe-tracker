module Api
  class ChokepointsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      snapshot = ChokepointSnapshotService.fetch_or_enqueue
      payload = snapshot&.payload.presence || ChokepointSnapshotService.empty_payload
      chokepoints = payload["chokepoints"] || payload[:chokepoints] || []

      render json: {
        chokepoints: chokepoints,
        count: chokepoints.size,
        snapshot_status: snapshot_status_for(snapshot),
      }
    end

    def show
      snapshot = ChokepointSnapshotService.fetch_or_enqueue
      payload = snapshot&.payload.presence || ChokepointSnapshotService.empty_payload
      chokepoint = find_chokepoint(payload, params[:id])
      return render json: { error: "Not found" }, status: :not_found unless chokepoint

      commodity_key = SupplyChainLensService.primary_commodity_for_chokepoint(chokepoint["id"] || chokepoint[:id])
      supply_chain_lens = commodity_key.present? ? SupplyChainLensService.call(
        chokepoint_key: chokepoint["id"] || chokepoint[:id],
        commodity_key: commodity_key,
      ) : nil

      render json: {
        chokepoint: chokepoint.deep_dup.merge(
          "primary_commodity_key" => commodity_key,
          "supply_chain_lens" => supply_chain_lens,
        ),
        snapshot_status: snapshot_status_for(snapshot),
      }
    end

    private

    def snapshot_status_for(snapshot)
      return "pending" unless snapshot
      return "ready" if snapshot.fresh? && snapshot.status == "ready"

      snapshot.status == "error" ? "error" : "stale"
    end

    def find_chokepoint(payload, identifier)
      chokepoints = payload["chokepoints"] || payload[:chokepoints] || []
      raw = identifier.to_s.strip.downcase

      chokepoints.find do |entry|
        candidates = [
          entry["id"], entry[:id],
          entry["name"], entry[:name],
          entry["name"]&.tr(" ", "_"), entry[:name]&.tr(" ", "_"),
        ].compact.map { |value| value.to_s.downcase }
        candidates.include?(raw)
      end
    end
  end
end
