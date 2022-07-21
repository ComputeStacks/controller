##
# Custom Host Entries for a container service
#
# @!attribute container_service
#   @return [ContainerService]
# @!attribute hostname
#   @return [String]
# @!attribute keep_updated
#   @return [Boolean] if true, we will continually update the value.
# @!attribute ipaddr
#   @return [String]
# @!attribute template
#   @return [ContainerImage::CustomHostEntry]
class ContainerService::HostEntry < ApplicationRecord

  include Auditable

  belongs_to :container_service, class_name: 'Deployment::ContainerService'
  belongs_to :template,
             class_name: 'ContainerImage::CustomHostEntry',
             inverse_of: :children,
             optional: true

end
