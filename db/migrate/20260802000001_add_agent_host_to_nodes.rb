class AddAgentHostToNodes < ActiveRecord::Migration[7.2]
  def change
    # agent_host: optional override for the address the controller dials to reach this
    #   node's cs-agent (port 8500). That channel is the one control-plane transport
    #   still on plain HTTP, so it can be pointed at an encrypted path (e.g. a Tailscale
    #   address) independently of primary_ip, which stays the Docker/SSH/HAProxy/
    #   metadata.internal address. NULL/blank falls back to primary_ip.
    add_column :nodes, :agent_host, :string
  end
end
