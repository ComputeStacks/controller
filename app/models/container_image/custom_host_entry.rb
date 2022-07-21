##
# Custom Host Entries for a container images
#
# @!attribute container_image
#   @return [ContainerImage]
# @!attribute hostname
#   @return [String]
# @!attribute source_image
#   @return [ContainerImage]
class ContainerImage::CustomHostEntry < ApplicationRecord

  include Auditable

  belongs_to :container_image
  belongs_to :source_image, class_name: 'ContainerImage'
  has_many :children,
           class_name: 'ContainerService::HostEntry',
           foreign_key: 'template_id',
           dependent: :nullify

  validates :hostname, presence: true

end
