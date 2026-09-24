##
# The controller's local projection of one cs-agent `repository` (observed borg repo
# state), keyed by the volume/repo name. Backs Volume#repo_info, replacing the old
# Consul `borg/repository/<name>` read. Eventually-consistent cache — the authoritative
# "archive created" signal is a completed volume.backup task result, not this row.
class AgentRepository < ApplicationRecord
  belongs_to :node, optional: true

  validates :name, presence: true, uniqueness: true
end
