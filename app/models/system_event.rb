##
# System events
#
# message:string
# log_level: [debug,info,warn]
# data:text
#
# event_code:string `echo $(openssl rand -hex 8) | tr -d '\n' | pbcopy`
#
class SystemEvent < ApplicationRecord

  scope :sorted, -> { order(created_at: :desc) }

  belongs_to :audit, optional: true
  serialize :data

end
