class AddRegionToIngressRules < ActiveRecord::Migration[6.1]
  def change

    add_column :network_ingress_rules, :region_id, :bigint
    add_index :network_ingress_rules, :region_id

  end
end
