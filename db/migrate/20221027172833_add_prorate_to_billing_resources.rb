class AddProrateToBillingResources < ActiveRecord::Migration[7.0]
  def change
    add_column :billing_resources, :prorate, :boolean, default: false, null: false
  end
end
