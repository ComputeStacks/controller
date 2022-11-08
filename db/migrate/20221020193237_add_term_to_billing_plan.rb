class AddTermToBillingPlan < ActiveRecord::Migration[7.0]
  def change
    add_column :billing_plans, :term, :string, default: 'hour', null: false
  end
end
