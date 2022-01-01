##
# Dns Zone Collaborator
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute dns_zone
#   @return [Dns::Zone]
#
# @!attribute collaborator
#   @return [User]
#
class Dns::ZoneCollaborator < ApplicationRecord

  include Auditable
  include Collaborations

  belongs_to :dns_zone, class_name: 'Dns::Zone', foreign_key: 'dns_zone_id'
  belongs_to :collaborator, class_name: 'User', foreign_key: 'user_id'

  has_many :records, through: :dns_zone

  after_create_commit :notify_user

  def resource_owner
    dns_zone.user
  end

  private

  def notify_user
    return if ActiveRecord::Type::Boolean.new.cast(skip_confirmation)
    CollaborationMailer.dns_invite(dns_zone, collaborator).deliver_later
  end

end
