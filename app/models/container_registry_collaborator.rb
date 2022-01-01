##
# Container Registry Collaborator
#
# Model holding a Registry and Collaborator (User)
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute container_registry
#   @return [ContainerRegistry]
#
# @!attribute collaborator
#   @return [User]
#
class ContainerRegistryCollaborator < ApplicationRecord

  include Auditable
  include Collaborations

  belongs_to :container_registry
  belongs_to :collaborator, class_name: 'User', foreign_key: 'user_id'

  validates :container_registry, uniqueness: { scope: :collaborator }
  validates :collaborator, uniqueness: { scope: :container_registry }

  after_create_commit :notify_user

  def resource_owner
    container_registry.user
  end

  private

  def notify_user
    return if ActiveRecord::Type::Boolean.new.cast(skip_confirmation)
    CollaborationMailer.registry_invite(container_registry, collaborator).deliver_later
  end

end
