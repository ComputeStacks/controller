module Regions
  module RegionMetrics
    extend ActiveSupport::Concern

    # Returns allocated usage as a %.
    def current_allocated_usage
      cpu = 0.0
      memory = 0
      avail_cpu = nodes.sum { |i| i.metric_cpu_cores[:cpu] }
      avail_mem = nodes.sum { |i| i.metric_memory(:MB)[:memory] }
      container_services.each do |service|
        service.subscriptions.each do |sub|
          next if sub.package.nil?
          cpu += sub.package.cpu
          memory += sub.package.memory
        end
      end
      {
        cpu: {
          used: cpu,
          available: avail_cpu,
          usage: avail_cpu.zero? ? 100 : ((cpu.to_f / avail_cpu) * 100).to_i
        },
        memory: {
          used: memory,
          available: avail_mem,
          usage: avail_mem.zero? ? 100 : ((memory.to_f / avail_mem) * 100).to_i
        }
      }
    end

    # Currently used to display stats on admin dashboard
    def resource_usage
      mem_usages = []
      cpu_usages = []
      disk_usages = []
      nodes.where(active: true).each do |i|
        m = i.metric_memory_usage
        mem_usages << m unless m.nil?
        c = i.metric_cpu_usage
        cpu_usages << c unless c.nil?
        disk = i.metric_disk_usage
        next if disk.nil?
        primary_disk = nil
        # choose the disk to use for calculating available storage.
        # Priority is /var/lib/docker, otherwise /.
        disk.each do |dd|
          if dd[:mountpoint] == '/'
            primary_disk = dd if primary_disk.nil? || primary_disk[:mountpoint] != '/var/lib/docker'
          end
          primary_disk = dd if dd[:mountpoint] == '/var/lib/docker'
        end
        if primary_disk
          du = primary_disk[:usage]
          disk_usages << du unless du.nil?
        end
      end
      mem_usages << 0.0 if mem_usages.empty?
      cpu_usages << 0.0 if cpu_usages.empty?
      disk_usages << 0.0 if disk_usages.empty?
      {
        cpu: cpu_usages.average&.round(4),
        memory: mem_usages.average&.round(4),
        disk: disk_usages.average&.round(4),
        containers: container_count
      }
    rescue => e
      ExceptionAlertService.new(e, 'cdf613d0d76a98c7').perform
      { cpu: 0.0, memory: 0.0, disk: 0.0, containers: 0 }
    end

    def metric_list_regions
      metric_client.call.label('region')
    end

  end
end
