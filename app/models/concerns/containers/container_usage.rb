module Containers
  module ContainerUsage
    extend ActiveSupport::Concern


    def billing_volume_usage
      total_containers = service.containers.count.to_f
      total_containers = total_containers.zero? ? 1 : total_containers
      service.owned_volumes.sum(:usage) / total_containers
    end

    def billing_local_disk_usage
      container_usage = metric_current_disk_usage
      container_usage.nil? ? 0.0 : container_usage
    end

    def billing_backup_usage
      usage = 0.0
      total_containers = service.containers.count.to_f
      service.volumes.each do |vol|
        begin
          data = vol.repo_info
          usage += data['usage'] if data['usage']
        rescue => e
          ExceptionAlertService.new(e, '150d335a81465d1a').perform
          next
        end
      end
      (usage.zero? ? usage : (usage / BYTE_TO_GB).round(4)) / total_containers
    end

    # Returns the used bandwidth
    def billing_current_bandwidth
      usage = service.bill_bw_by_lb? ? metric_lb_bytes_out : metric_bytes_out
      usage.zero? ? usage : (usage / BYTE_TO_GB).round(8)
    rescue => e
      ExceptionAlertService.new(e, 'f15ff18825639b49').perform
      0.0
    end

  end
end
