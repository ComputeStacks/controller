##
# Container Image Relationships
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute container_image
#   @return [ContainerImage]
#
# @!attribute dependency
#   @return [ContainerImage]
#
class ContainerImage::ImageRel < ApplicationRecord

  include Auditable

  belongs_to :container_image,
             class_name: 'ContainerImage',
             foreign_key: 'container_image_id'

  belongs_to :dependency,
             class_name: "ContainerImage",
             foreign_key: "requires_container_id"

  validate :can_link?
  validate :is_unique?

  attr_accessor :bypass_auth_check

  private

  def is_unique?
    if container_image.dependency_parents.include?(self)
      errors.add(:base, "These images are already linked.")
    end
  end

  def can_link?
    return true if bypass_auth_check
    if current_user.nil?
      errors.add(:base, "Missing current user, unable to validate permission")
    elsif !container_image.user.nil?
      if !current_user.is_admin && current_user != container_image.user
        errors.add(:base, "You do not have permission to link this image.")
      end
      unless current_user.is_admin
        if dependency.user && dependency.user != current_user
          errors.add(:base, "You do not have permission to link to this image")
        end
      end
    end
  end


end
