##
# Project SSH Keys
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
# @!attribute deployment
#   @return [Deployment]
#
class Deployment::SshKey < ApplicationRecord

  include Auditable
  include SshPublicKey

  belongs_to :deployment

  after_create :reload_ssh_keys
  before_destroy :reload_ssh_keys

  private

  def reload_ssh_keys
    return unless current_audit
    ProjectWorkers::RefreshMetadataSshWorker.perform_async deployment.id, current_audit.id
  end

end
