##
# User SSH Key
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute [r] label
#   @return [String] label taken from comment section of uploaded public key.
#
# @!attribute pubkey
#   @return [String] SSH Public Key
#
# @!attribute created_at
#   @return [DateTime]
#
# @!attribute updated_at
#   @return [DateTime]
#
# @!attribute user
#   @return [User]
#
class UserSshKey < ApplicationRecord

  include Auditable
  include SshPublicKey

  belongs_to :user

  after_create :reload_ssh_keys
  before_destroy :reload_ssh_keys

  def self.find_for_project(project)
    k = []
    project.user.ssh_keys.each do |i|
      k << i unless k.include?(i)
    end
    project.deployment_collaborators.active.each do |c|
      c.collaborator.ssh_keys.each do |i|
        k << i unless k.include?(i)
      end
    end
    k
  end

  private

  def reload_ssh_keys
    return unless current_audit
    Deployment.find_all_for(user).each do |d|
      ProjectWorkers::RefreshMetadataSshWorker.perform_async d.id, current_audit.id
    end
  end

end
