module Api
  class SupplyChainController < ApplicationController
    skip_before_action :authenticate_user!

    def dependency_map
      render_supply_chain_slice(:dependency_map)
    end

    def reserve_runway
      render_supply_chain_slice(:reserve_runway)
    end

    def downstream_pathway
      render_supply_chain_slice(:downstream_pathway)
    end

    private

    def render_supply_chain_slice(slice_key)
      chokepoint_key = params[:chokepoint_key].to_s
      commodity_key = params[:commodity_key].to_s
      return render json: { error: "commodity_key and chokepoint_key are required" }, status: :unprocessable_entity if commodity_key.blank? || chokepoint_key.blank?

      lens = SupplyChainLensService.call(chokepoint_key: chokepoint_key, commodity_key: commodity_key)

      render json: {
        chokepoint_key: lens[:chokepoint_key],
        chokepoint_name: lens[:chokepoint_name],
        commodity_key: lens[:commodity_key],
        commodity_name: lens[:commodity_name],
        slice_key => lens.fetch(slice_key),
      }
    end
  end
end
