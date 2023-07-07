class ModifyNetworks < ActiveRecord::Migration[7.0]
  def change
    # Grow network IDs
    change_column :networks, :id, :bigint
    change_column :network_cidrs, :network_id, :bigint
    change_column :network_cidrs, :id, :bigint

    ActiveRecord::Base.connection.execute "ALTER SEQUENCE public.networks_id_seq as bigint"
    ActiveRecord::Base.connection.execute "ALTER SEQUENCE public.network_cidrs_id_seq as bigint"

    add_column :networks, :deployment_id, :bigint
    add_column :networks, :is_shared, :boolean, default: true, null: false
    add_column :networks, :region_id, :bigint
    add_column :networks, :subnet, :cidr
    add_column :networks, :parent_network_id, :bigint

    add_column :regions, :p_net_size, :integer, default: 27, null: false

    # `alter table only regions alter column network_driver set default 'bridge';`
    add_column :regions, :network_driver, :string, default: 'bridge', null: false

    remove_column :networks, :is_public, :boolean
    remove_column :networks, :is_ipv4, :boolean
    remove_column :networks, :cross_region, :boolean

    add_index :networks, :deployment_id
    add_index :networks, :is_shared
    add_index :networks, :region_id
    add_index :networks, :parent_network_id

  end
end
