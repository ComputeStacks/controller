##
# Rebalance containers on nodes.
# Should be run from the controller using `cstacks console`
# This will not migrate SFTP containers.

# You can easily figure this out by running: `Region.pluck(:id, :name)`
region_id = 5

dry_run = true # Set to false to actually perform the migration!

region = Region.find(region_id)

per_node = region.containers.count / region.nodes.count

region.nodes.each do |node|
  if node.containers.count <= per_node
    puts "[SKIP] #{node.hostname} is #{per_node - node.containers.count} containers behind."
    next
  end
  qty = node.containers.count - per_node
  puts "[BALANCE] #{node.hostname} needs to lose #{qty} containers..."
  # find up to `qty` containers to migrate
  to_migrate = []
  region.containers.each do |container|
    next if container.package.nil?
    next unless container.can_migrate?
    to_migrate << container
    break if to_migrate.count == qty
  end
  puts "...found #{to_migrate.count} eligible for migration..."
  to_migrate.each do |container|
    if dry_run
      puts "...selected #{container.name} for migration (DRY RUN)."
    else
      puts "...scheduling #{container.name} for migration."
      audit = Audit.create_from_object!(container, 'updated', '127.0.0.1')
      event = EventLog.create!(
        locale: 'container.migrating',
        locale_keys: { 'container' => container.name },
        event_code: '4c7a96039fac57d9',
        status: 'pending',
        audit: audit
      )
      event.containers << container
      event.deployments << container.deployment
      event.container_services << container.service
      ContainerWorkers::MigrateContainerWorker.perform_async container.to_global_id.uri, event.to_global_id.uri
    end
  end
end; 0

