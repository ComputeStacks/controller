class AddCustomerNoticeToNodes < ActiveRecord::Migration[7.2]
  # A message shown to customers while the node is in maintenance or offline.
  # Separate from maintenance_reason, which is internal and never exposed.
  def change
    add_column :nodes, :customer_notice, :text
  end
end
