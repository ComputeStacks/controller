class AddBillPerToBillingResources < ActiveRecord::Migration[7.0]
  def change
    add_column :billing_resources, :bill_per, :string, default: 'service', null: false
  end
end
