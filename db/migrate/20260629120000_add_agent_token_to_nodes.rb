class AddAgentTokenToNodes < ActiveRecord::Migration[7.2]
  def change
    # Encrypted per-node admin Bearer the controller uses for privileged cs-agent
    # calls (Agent::Client). Minted controller-side; only its sha256 is exposed.
    add_column :nodes, :agent_token_encrypted, :text
  end
end
