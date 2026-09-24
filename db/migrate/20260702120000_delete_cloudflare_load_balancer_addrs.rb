class DeleteCloudflareLoadBalancerAddrs < ActiveRecord::Migration[7.2]
  # Cloudflare IPs now live in a global file (see ProxyIpList), not per-load-balancer
  # `load_balancer_addr` rows. Remove the old Cloudflare rows (and their taggings);
  # everything else (Bunny, public/internal/connect roles) is left untouched.
  def up
    execute(<<~SQL)
      DELETE FROM taggings
       WHERE taggable_type = 'LoadBalancerAddr'
         AND taggable_id IN (SELECT id FROM load_balancer_addrs WHERE label = 'Cloudflare');
    SQL
    execute("DELETE FROM load_balancer_addrs WHERE label = 'Cloudflare';")
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
