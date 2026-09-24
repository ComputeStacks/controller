##
# The controller's local projection of one cs-agent `action_request` (a container
# asking the controller to perform an action on its own project). Populated by
# Agent::ChangelogProjector (blind, idempotent insert-if-absent keyed by action_id);
# executed by ContainerActionServices::Dispatch off the state machine in
# ContainerActionRequests::StateManager.
class ContainerActionRequest < ApplicationRecord
  include ContainerActionRequests::StateManager

  belongs_to :node, optional: true
  belongs_to :deployment, optional: true

  validates :action_id, presence: true, uniqueness: true
  validates :action_type, presence: true
end
