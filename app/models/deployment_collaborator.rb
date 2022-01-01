##
# Project Collaborators
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute collaborator
#   @return [User]
#
class DeploymentCollaborator < ApplicationRecord

  include Auditable
  include Collaborations

  belongs_to :deployment
  belongs_to :collaborator, class_name: 'User', foreign_key: 'user_id'

  has_many :container_services, through: :deployment
  has_many :container_images, through: :deployment
  has_many :containers, through: :deployment, inverse_of: :deployed_containers

  validates :deployment, uniqueness: { scope: :collaborator }
  validates :collaborator, uniqueness: { scope: :deployment }

  after_create_commit :notify_user

  after_save :reload_ssh_keys

  def resource_owner
    deployment.user
  end

  private

  def notify_user
    return if ActiveRecord::Type::Boolean.new.cast(skip_confirmation)
    CollaborationMailer.project_invite(deployment, collaborator).deliver_later
  end

  ##
  # Reload SSH Keys
  #
  # If active, always reload, otherwise only if active is changed.
  def reload_ssh_keys
    if active || active_previously_changed?
      return unless current_audit
      Deployment.find_all_for(collaborator).each do |d|
        ProjectWorkers::RefreshMetadataSshWorker.perform_async d.id, current_audit.id
      end
    end
  end

end
