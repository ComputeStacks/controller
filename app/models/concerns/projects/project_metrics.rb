module Projects
  module ProjectMetrics
    extend ActiveSupport::Concern

    class_methods do

      ##
      # Find deployments given their disk size
      # is above a specific value
      def project_ids_by_disk_usage(disk_size = 0)
        #count by (container_label_com_computestacks_deployment_id) (container_fs_usage_bytes > 1073741274)
        i = (disk_size * BYTE_TO_GB).to_i
        d = []
        MetricClient.all.each do |mc|
          begin
            response = mc.call.query_range(
              query: "count by(container_label_com_computestacks_deployment_id)" \
                     "(container_fs_usage_bytes > #{i})",
              start: 1.hour.ago.to_i,
              end: Time.now.to_i,
              step: 15
            )
            response['result'].each do |r|
              next unless r.dig('metric', 'container_label_com_computestacks_deployment_id')
              id = r['metric']['container_label_com_computestacks_deployment_id'].to_i
              d << id unless id.zero?
            end
          rescue => e
            ExceptionAlertService.new(e, '7a9494b8bf8cca5c').perform
            next
          end
        end
        d
        # Deployment.where( Arel.sql %Q(id IN (#{d.join(', ')}) ))
      end

    end

    # Calculate bandwidth used this period
    def current_bandwidth(reset_cache = false)
      cache_key = "d_bw_#{id}"
      Rails.cache.fetch(cache_key, force: reset_cache, expires_in: 2.hours) do
        total = BigDecimal("0.00")
        services.each { |i| total += i.bandwidth_this_period }
        total
      end
    end

    def current_storage(reset_cache = false)
      cache_key = "d_vol_#{id}"
      Rails.cache.fetch(cache_key, force: reset_cache, expires_in: 2.hours) do
        u = 0.0
        deployed_containers.each do |c|
          u += c.billing_volume_usage
          u += c.billing_local_disk_usage
        end
        u
      end
    end

    def run_rate(reset_cache = false)
      cache_key = "d_run_rate_#{id}"
      Rails.cache.fetch(cache_key, force: reset_cache, expires_in: 2.hours) do
        subscriptions.all_active.inject(0) { |sum,item| sum += item.run_rate }
      end
    end

    def last_event
      event_logs.select(:id, :created_at, :updated_at).sorted.limit(1).first.updated_at
    rescue
      nil
    end

  end
end
