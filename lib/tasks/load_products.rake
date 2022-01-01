task load_products: :environment do

  puts "Creating Sample Products"

  plan = BillingPlan.first
  if plan.nil?
    plan = BillingPlan.create!(name: 'default', is_default: true)

    package_a_product = Product.create!(
      name: 'container_s',
      label: 'ContainerS',
      kind: 'package'
    )
    package_a_product.create_package(
      cpu: 1,
      memory: 512,
      storage: 10,
      local_disk: 2,
      bandwidth: 3000
    )
    package_a_resource = plan.billing_resources.create!(product: package_a_product)
    package_a_resource.prices.create!(price: 0.00343, term: 'hour', currency: ENV['CURRENCY'], billing_phase: package_a_resource.billing_phases.first, regions: Region.all)

    package_b_product = Product.create!(
      name: 'container_m',
      label: 'ContainerM',
      kind: 'package'
    )
    package_b_product.create_package(
      cpu: 1,
      memory: 1024,
      storage: 15,
      local_disk: 5,
      bandwidth: 3000
    )
    package_b_resource = plan.billing_resources.create!(product: package_b_product)
    package_b_resource.prices.create!(price: 0.00685, term: 'hour', currency: ENV['CURRENCY'], billing_phase: package_b_resource.billing_phases.first, regions: Region.all)

    package_c_product = Product.create!(
      name: 'container_l',
      label: 'ContainerL',
      kind: 'package'
    )
    package_c_product.create_package(
      cpu: 2,
      memory: 2048,
      storage: 25,
      local_disk: 10,
      bandwidth: 3000
    )
    package_c_resource = plan.billing_resources.create!(product: package_c_product)
    package_c_resource.prices.create!(price: 0.0137,term: 'hour', currency: ENV['CURRENCY'], billing_phase: package_c_resource.billing_phases.first, regions: Region.all)

    # Storage
    storage_product = Product.create!(
      name: 'storage',
      label: 'Storage',
      kind: 'resource',
      unit: 1,
      unit_type: 'GB',
      resource_kind: 'storage',
      is_aggregated: false # billed per hour/month, per GB
    )
    storage_overage_resource = plan.billing_resources.create!(product: storage_product)
    storage_overage_resource.prices.create!(price: 0.0001369863, currency: ENV['CURRENCY'], billing_phase: storage_overage_resource.billing_phases.first, term: 'hour', regions: Region.all)

    # Local Disk
    local_disk_product = Product.create!(
      name: 'local_disk',
      label: 'Temporary Disk',
      kind: 'resource',
      unit: 1,
      unit_type: 'GB',
      resource_kind: 'local_disk',
      is_aggregated: false
    )
    local_disk_resource = plan.billing_resources.create! product: local_disk_product
    local_disk_resource.prices.create! price: 0.0001369863, currency: ENV['CURRENCY'], term: 'hour', billing_phase: local_disk_resource.billing_phases.first, regions: Region.all

    # Bandwidth
    bandwidth_product = Product.create!(
      name: 'bandwidth',
      label: 'Bandwidth',
      kind: 'resource',
      unit: 1,
      unit_type: 'GB',
      resource_kind: 'bandwidth',
      is_aggregated: true # Once you used it, you pay for it.
    )
    bandwidth_resource = plan.billing_resources.create!(product: bandwidth_product)
    bandwidth_resource.prices.create!(price: 0, max_qty: 1024, currency: ENV['CURRENCY'], billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # First 1TB is free
    bandwidth_resource.prices.create!(price: 0.09, max_qty: 10240, currency: ENV['CURRENCY'], billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 1TB - 10TB
    bandwidth_resource.prices.create!(price: 0.07, max_qty: nil, currency: ENV['CURRENCY'], billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 10TB+

    # Backup
    backup_product = Product.create!(
      name: 'backup',
      label: 'Backup & Template Storage',
      kind: 'resource',
      unit: 1,
      unit_type: 'GB',
      resource_kind: 'backup',
      is_aggregated: false
    )
    backup_resource = plan.billing_resources.create!(product: backup_product)
    backup_resource.prices.create!(price: 0.0000684932, currency: ENV['CURRENCY'], billing_phase: backup_resource.billing_phases.first, term: 'hour', regions: Region.all)

    BillingResourcePrice.all.each do |i|
      i.regions << Region.first
    end

    UserGroup.all.each do |g|
      g.update billing_plan: plan
    end
  end

end
