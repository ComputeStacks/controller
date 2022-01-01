require 'clockwork'
require './config/boot'
require './config/environment'

module Clockwork
  handler do |job, time|
    puts "Running #{job}, at #{time}"
  end

  every(5.minutes, 'nodes.heartbeat') do
    NodeWorkers::HeartbeatWorker.perform_async
  end

  every(7.minutes, 'nodes.health_check') do
    NodeWorkers::HealthCheckWorker.perform_async
  end

  every(10.minutes, 'sftp.cleanup') do
    ContainerWorkers::SftpCleanupWorker.perform_async
  end

  every(15.minutes, 'le.provision_certs') do
    LetsEncryptWorkers::GenerateCertWorker.perform_async nil
  end

  every(20.minutes, 'volume.cleanup') do
    VolumeWorkers::TrashVolumeWorker.perform_async
  end

  every(30.minutes, 'project.cache') do
    ProjectWorkers::ProjectCacheWorker.perform_async
  end

  every(1.hour, 'billing.phases', at: '**:02') do
    SubscriptionWorkers::PhaseAdvanceWorker.perform_async
  end

  every(1.hour, 'le.validate_domains') do
    # This should already have happened, but run here to pick up any errors
    LetsEncryptWorkers::ValidateDomainWorker.perform_async
  end

  every(3.hours, 'volume.metrics', at: '**:00') do
    RegionWorkers::VolumeUsageWorker.perform_async
  end

  every(3.hours, 'billing.usage', at: '**:20') do
    SubscriptionWorkers::CollectUsageWorker.perform_async
  end

  every(4.hours, 'system.clean_stale_events') do
    JobSystem.perform_async 'clean_stale_events'
  end

  every(12.hours, 'system.clean_orders') do
    JobSystem.perform_async 'clean_orders'
    JobSystem.perform_async 'clean_le_auth'
  end

  every(1.day, 'volume.sync', at: '03:33') do
    VolumeWorkers::SyncLocalVolumeWorker.perform_async
  end

  every(1.day, 'system.metrics', at: '01:00') do
    JobSystem.perform_async 'clean_container_stats'
  end

  every(1.day, 'nodes.daily_maintenance', at: '01:10') do
    NodeWorkers::UpdateImageWorker.perform_async
    ImageWorkers::UpdateSshImageWorker.perform_async
  end

  every(1.day, 'system.cleanup', at: '03:10') do
    EventWorkers::StaleEventWorker.perform_async
  end

  every(1.day, 'billing.consumables', at: '23:00') do
    SubscriptionWorkers::ProcessUsageWorker.perform_async
  end

  every(3.days, 'system.prune_sys_events', at: '01:00') do
    JobSystem.perform_async 'prune_sys_events'
    EventWorkers::PruneEventWorker.perform_async
  end

  every(5.days, 'load_balancers.update_proxy_ip', at: '03:00') do
    LoadBalancerWorkers::UpdateProxyServiceWorker.perform_async
  end

  error_handler do |error|
    Raven::Context.clear!
    Raven.tags_context(event_code: "c698b5e4da4c518c")
    Raven.capture_exception(error)
    Raven::Context.clear!
  end
end
