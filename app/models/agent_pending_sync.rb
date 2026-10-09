##
# A dropped agent write that must be re-pushed: "(region, subject, kind, key) is
# out of sync". Replay recomputes the body from current data.
class AgentPendingSync < ApplicationRecord
  belongs_to :region
  belongs_to :node, optional: true
end
