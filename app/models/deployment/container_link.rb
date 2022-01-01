# Container Links
#
# Create dependencies between container services.
class Deployment::ContainerLink < ApplicationRecord

  belongs_to :service, class_name: "Deployment::ContainerService", foreign_key: 'service_id', optional: true
  belongs_to :service_resource, class_name: "Deployment::ContainerService", foreign_key: 'service_resource_id', optional: true

end
