class AddProxyBunnyToLoadBalancers < ActiveRecord::Migration[7.2]
  def change
    add_column :load_balancers, :proxy_bunny, :boolean, default: true, null: false
    add_column :network_ingress_rules, :restrict_bunny, :boolean, default: false, null: false
  end
end
