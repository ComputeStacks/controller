##
# ContainerImageCollaborator
#
# Model holding an Image and Collaborator (User)
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute container_image
#   @return [ContainerImage]
#
# @!attribute collaborator
#   @return [User]
#
class ContainerImageCollaborator < ApplicationRecord

  include Auditable
  include Collaborations

  belongs_to :container_image
  belongs_to :collaborator, class_name: 'User', foreign_key: 'user_id'

  validates :container_image, uniqueness: { scope: :collaborator }
  validates :collaborator, uniqueness: { scope: :container_image }

  after_create_commit :notify_user

  def resource_owner
    container_image.user
  end

  private

  def notify_user
    return if ActiveRecord::Type::Boolean.new.cast(skip_confirmation)
    CollaborationMailer.image_invite(container_image, collaborator).deliver_later
  end

end
