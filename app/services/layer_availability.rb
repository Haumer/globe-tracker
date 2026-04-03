class LayerAvailability
  DISABLED_LAYERS = %w[
    trains
    railways
    shipping_lanes
  ].freeze

  class << self
    attr_writer :disabled_layers

    def disabled?(layer_key)
      disabled_layers.include?(normalize(layer_key))
    end

    def enabled?(layer_key)
      !disabled?(layer_key)
    end

    def disabled_layers
      @disabled_layers || DISABLED_LAYERS
    end

    private

    def normalize(layer_key)
      layer_key.to_s.underscore
    end
  end
end
