module Containers
  module ContainerRuntime
    extend ActiveSupport::Concern

    def runtime_config(audit = nil)
      # Sanity checks
      return nil if service.nil?
      return nil if deployment.nil?
      return nil if image_variant.nil?
      return nil if container_image.nil?

      return nil unless setup_custom_hosts!(audit)

      return nil if local_ip.blank?

      # Config
      c = {
        'name' => name,
        'Hostname' => name,
        'Domainname' => "service.internal",
        'ExposedPorts' => {},
        'Labels' => {
          'com.computestacks.service_id' => service.id.to_s,
          'com.computestacks.deployment_id' => deployment.id.to_s,
          'com.computestacks.image_name' => image_variant.full_image_path
        },
        'Image' => image_variant.full_image_path,
        'HostConfig' => {
          'PortBindings' => {},
          'NetworkMode' => ip_address.network.name,
          'VolumeDriver' => 'local',
          'LogConfig' => log_driver_config, # Containerized.log_driver_config
        },
        'NetworkingConfig' => {
          'EndpointsConfig' => {
            ip_address.network.name => {
              'IPAMConfig' => {
                'IPv4Address' => local_ip
              }
            }
          }
        }
      }

      unless health_check_config.nil?
        c['Healthcheck'] = health_check_config
      end

      if region.has_clustered_networking?
        c['Labels']['org.projectcalico.label.token'] = deployment.token
        c['Labels']['org.projectcalico.label.service'] = service.name
      end
      runtime_env.each do |k, v|
        (c['Env'] ||= []) << "#{k}=#{v}"
      end
      service.volumes.where(nodes: { id: node.id }).joins(:nodes).distinct.each do |vol|
        vm = vol.volume_maps.find_by container_service: service
        next if vm.nil?
        (c['HostConfig']['Binds'] ||= []) << "#{vm.volume.name}:#{vm.mount_path.strip}:#{vm.mount_ro ? 'ro' : 'rw'}"
      end
      cmd = parsed_command
      if cmd
        if cmd[0..9] == "/bin/sh -c"
          c['CMD'] = ["/bin/sh", "-c", cmd.gsub("/bin/sh -c", "")]
        elsif cmd[0..11] == "/bin/bash -c"
          c['CMD'] = ["/bin/sh", "-c", cmd.gsub("/bin/sh -c", "")]
        else
          cmd.split(' ').each do |i|
            (c['Cmd'] ||= []) << i
          end
        end
      end
      c['HostConfig']['NanoCPUs'] = cpu ? (cpu * 1e9).to_i : (1 * 1e9).to_i
      m = memory.nil? ? 256 : memory
      # Also change `resize_job.rb`.
      # 1 GiB = 1073741824 on docker inspect
      # 1073741824 / 1024 = 1048576
      mem_value = (m * 1048576).to_i
      mem_swap = mem_value
      mem_swappiness = nil

      if subscription&.package
        p = subscription.package
        mem_swap = mem_value + (p.memory_swap * 1048576).to_i if p.memory_swap
        mem_swappiness = p.memory_swappiness if p.memory_swappiness
      end
      c['HostConfig']['Memory'] = mem_value
      c['HostConfig']['MemorySwap'] = mem_swap
      c['HostConfig']['MemorySwappiness'] = mem_swappiness if mem_swappiness

      c['HostConfig']['ExtraHosts'] = custom_host_entries

      c['HostConfig'].merge! node.container_io_limits
      service.service_plugins.each do |p|
        c = p.apply_plugin_config! c
      end

      ##
      # SHM Size Override
      shm = service.shm_size.zero? ? container_image.shm_size : service.shm_size
      c['HostConfig']['ShmSize'] = shm unless shm.zero?

      c
    rescue => e
      ExceptionAlertService.new(e, 'a974dd3087e0cf79').perform
      l = event_logs.create!(
        status: 'alert',
        notice: true,
        locale: 'deployment.errors.fatal',
        event_code: 'a974dd3087e0cf79',
        audit: audit
      )
      l.event_details.create!(data: "Error generating runtime config for container #{name}: #{e.message}", event_code: 'a974dd3087e0cf79')
      l.deployments << deployment if deployment
      l.users << user if user
      nil
    end

    # Service command, parsed
    def parsed_command
      return nil if service.command&.strip.blank?
      raw_command = service.command.strip
      data = Liquid::Template.parse(raw_command)
      vars = { 'service_name_short' => var_lookup('build.self.service_name_short') }
      service.setting_params.each do |param|
        vars[param.name] = var_lookup("build.settings.#{param.name}")
      end
      data.render(vars)
    end

    # List host entries for docker
    # @return [Array]
    def custom_host_entries
      h = service.host_entries.map do |i|
        "#{i.hostname}:#{i.ipaddr}"
      end
      if Rails.env.production?
        h << "metadata.internal:#{node.primary_ip}"
      else
        h << "controller.cstacks.local:#{node.primary_ip}"
        h << "metadata.internal:#{node.primary_ip}"
      end
      h
    end

    private

    def setup_custom_hosts!(audit = nil)
      existing_host_rules = service.host_entries
      container_image.host_entries.each do |h|
        next unless existing_host_rules.select { |i| i.template == h }.empty?

        next if h.source_image.nil?

        host_ip = nil
        deployment.services.each do |s|
          if s.container_image == h.source_image
            host_ip = s.containers.first.local_ip
          end
        end
        next if host_ip.nil?

        # Orphaned host entries can be skipped from creation, and also
        # re-mapped to a template.
        if service.host_entries.where(hostname: h.hostname).exists?
          existing_record = service.host_entries.find_by template: nil, hostname: h.hostname, keep_updated: true
          if existing_record
            existing_record.update(
              template: h,
              ipaddr: host_ip
            )
          end
        else
          service.host_entries.create!(
            template: h,
            hostname: h.hostname,
            ipaddr: host_ip
          )
        end
      end
      true
    rescue => e
      ExceptionAlertService.new(e, 'ab4f48d8615f2ef7').perform
      l = event_logs.create!(
        status: 'alert',
        notice: true,
        locale: 'deployment.errors.fatal',
        event_code: 'ab4f48d8615f2ef7',
        audit: audit
      )
      l.event_details.create!(data: "Error generating custom hosts for #{name}: #{e.message}", event_code: 'ab4f48d8615f2ef7')
      l.deployments << deployment if deployment
      l.users << user if user
      nil
    end

    def runtime_env
      result = []
      vars = {
        'service_name_short' => var_lookup('build.self.service_name_short'),
        'default_domain' => var_lookup('build.self.default_domain')
      }
      service.setting_params.each do |param|
        vars[param.name] = var_lookup param.name
      end
      service.env_params.each do |i|
        case i.param_type
        when 'variable'
          val = var_lookup(i.value)
          if val.nil?
            raise "Unknown variable #{i.value}"
          end
          result << [i.name, val]
        when 'static'
          result << [i.name, Liquid::Template.parse(i.value).render(vars)]
        end
      end
      result + metadata_env_params
    end

    def health_check_config
      return nil if is_a?(Deployment::Sftp)
      case container_image.role
      when 'redis'
        { 'Test' => ["CMD", "redis-cli", "--raw", "incr", "ping"] }
      when 'mariadb'
        { 'Test' => ["CMD", '/usr/local/bin/healthcheck.sh', '--connect'] }
      when 'mysql'
        # mysql does not include the healthcheck script
        if container_image.registry_image_path == 'mariadb'
          { 'Test' => ["CMD", '/usr/local/bin/healthcheck.sh', '--connect'] }
        end
      when 'postgres'
        { 'Test' => ["CMD", "pg_isready"] }
      else
        nil
      end
    end

  end
end
