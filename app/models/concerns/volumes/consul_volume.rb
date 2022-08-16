module Volumes
  module ConsulVolume
    extend ActiveSupport::Concern

    # Compressed Backup Size
    #
    # Deduplicated and compressed size
    def backup_usage
      info = repo_info
      return 0.0 if info.empty?
      return 0.0 unless info['usage']
      (info['usage'] / BYTE_TO_GB).round(4)
    end

    # Total size of backup
    #
    # When uncompressed, this will be the total size on disk
    def backup_total_usage
      info = repo_info
      return 0.0 if info.empty?
      return 0.0 unless info['usage']
      (info['size'] / BYTE_TO_GB).round(4)
    end

    # List all backups for a Volume
    #
    # Reads the backup list from consul
    #
    # @example
    #     [{ id: integer, label: string, created: date }]
    #
    def list_archives
      return [] if repo_info.empty?
      list = []
      archives = repo_info['archives']
      return list if archives.nil?
      archives.reverse.each do |i|
        id = Base64.encode64(i).gsub("\n","")
        split_name = i.split('auto-')
        split_name = i.split('-m-') if split_name.count == 1
        if split_name.count > 1
          begin
            ts = Time.parse("#{split_name.last} UTC")
            list << {
              id: id,
              label: split_name.first == '' ? "auto" : split_name.first,
              created: ts
            }
          rescue
            list << {id: id, label: i}
          end
        else
          list << {id: id, label: i}
        end
      end
      list
    end

    # View info about a volume
    #
    # @example
    #   {
    #     "name"=>"6c13346f-c7a7-4157-b2d5-6c56da40a991",
    #     "usage"=>18522047, # Size on disk (deduplicated)
    #     "size"=>95738056, # Actual total size
    #     "archives"=>
    #     [
    #       "auto-2019-08-29T07:01:55-m-2019-08-29T07:01:55",
    #       "auto-2019-08-30T07:03:34-m-2019-08-30T07:03:34",
    #       "auto-2019-08-31T07:02:41-m-2019-08-31T07:02:41",
    #       "auto-2019-09-01T07:02:30-m-2019-09-01T07:02:30"
    #     ]
    #   }
    def repo_info
      data = Diplomat::Kv.get("borg/repository/#{name}", consul_config)
      JSON.parse(data)
    rescue
      {}
    end

    def consul_entry
      Diplomat::Kv.get("volumes/#{name}", consul_config)
    rescue #Diplomat::KeyNotFound
      nil
    end

    ##
    # Update consul volume config
    def update_consul!
      return true if nodes.empty?
      return true if nodes.online.empty?
      # Find existing record
      existing_entry = consul_entry

      if existing_entry
        existing_data = JSON.parse(existing_entry)
        data = default_consul_data
        data[:last_backup] = existing_data['last_backup']
      else
        data = default_consul_data
      end
      Diplomat::Kv.put("volumes/#{name}", data.to_json, consul_config)
    rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED => e
      SystemEvent.create!(
        message: "Error updating volume data on node",
        log_level: "warn",
        data: {
          error: e.message
        },
        event_code: '2a85dac45cdcfa58'
      )
      nil
    end

    ##
    # Determine the currently-assigned node for this volume
    def consul_active_node
      d = consul_entry
      if d.nil?
        s = consul_select_node
        s.blank? ? nil : Node.find_by(hostname: s)
      else
        response = Oj.load(d)
        Node.find_by(hostname: response["node"])
      end
    rescue => e
      ExceptionAlertService.new(e, "e69441ff0f3f4a0c").perform
      nil
    end

    private

    def default_consul_data
      {
        id: id,
        name: name,
        node: consul_select_node,
        backup: borg_enabled,
        freq: borg_freq,
        retention: {
          keep_hourly: borg_keep_hourly,
          keep_daily: borg_keep_daily,
          keep_weekly: borg_keep_weekly,
          keep_monthly: borg_keep_monthly,
          keep_annually: borg_keep_annually
        },
        last_backup: 1.year.ago.to_i,
        project_id: deployment&.id,
        service_id: container_service&.id,
        trash: to_trash,
        strategy: borg_strategy,
        backup_error_cont: borg_backup_error,
        restore_error_cont: borg_restore_error,
        pre_backup: borg_pre_backup,
        post_backup: borg_post_backup,
        pre_restore: borg_pre_restore,
        post_restore: borg_post_restore,
        rollback_restore: borg_rollback
      }
    end

    # Determine which node should initiate backups
    def consul_select_node
      if container_service.nil? || containers.empty?
        return "" if nodes.online.empty?
        nodes.online.first.hostname
      else
        n = nil
        containers.each do |c|
          next if c.node.nil?
          n = c.node if c.node.online?
          break unless n.nil?
        end
        n.nil? ? "" : n.hostname
      end
    end

    def consul_config
      return {} if Rails.env.test? # for test, we dont want any config here!
      return {} if nodes.online.empty?
      dc = region.nil? ? nodes.online.first.region.name.strip.downcase : region.name.strip.downcase
      token = region.nil? ? nodes.online.first.region.consul_token : region.consul_token
      return {} if token.blank?
      consul_ip = nodes.online.first.primary_ip
      {
        http_addr: Diplomat.configuration.options.empty? ? "http://#{consul_ip}:8500" : "https://#{consul_ip}:8501",
        dc: dc.blank? ? nil : dc,
        token: token
      }
    end

  end
end
