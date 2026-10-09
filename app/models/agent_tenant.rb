##
# Durable registry of the regions where a project's agent tenant exists.
# project_id has no FK: a row outlives its Project until the deprovision succeeds.
class AgentTenant < ApplicationRecord
  belongs_to :region
end
