class AddRatePeriodToBillingUsages < ActiveRecord::Migration[7.0]
  def change
    add_column :billing_usages, :rate_period, :integer, default: 1, null: false
  end
end
