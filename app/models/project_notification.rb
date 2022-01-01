##
# ProjectNotification
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute label
#   @return [String]
#
# @!attribute notifier
#   @return [email,keybase,matrix,slack,webhook,gchat]
#
# @!attribute value
#   Endpoint for notifier selected.
#   @return [String]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute rules
#   @return [Array]
#
class ProjectNotification < ApplicationRecord

  include Auditable
  include Notifications::Common

  belongs_to :deployment
  has_one :user, through: :deployment

end
