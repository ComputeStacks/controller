class MigrateNetworkRegions < ActiveRecord::Migration[7.0]
  def change

    existing_regions = ActiveRecord::Base.connection.execute "select * from networks_regions"
    existing_regions.each do |d|
      n = Network.find d['network_id'].to_i
      n.update_column :region_id, d['region_id'].to_i
    end

    existing_networks = ActiveRecord::Base.connection.execute "select * from networks"
    existing_networks.each do |i|
      next if i['cidr'].blank?
      n = Network.find i['id']
      n.update_column :subnet, IPAddr.new(i['cidr'])
    end

    remove_column :networks, :cidr, :string
    drop_join_table :regions, :networks


  end
end
