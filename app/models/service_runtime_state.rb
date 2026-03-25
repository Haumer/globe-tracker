class ServiceRuntimeState < ApplicationRecord
  validates :service_name, :desired_state, :reported_state, presence: true
end
