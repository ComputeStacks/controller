##
# User Notifications
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
# @!attribute user
#   @return [User]
#
# @!attribute rules
#   @return [Array]
#
class UserNotification < ApplicationRecord

  include Auditable
  include Notifications::Common

  belongs_to :user

end
