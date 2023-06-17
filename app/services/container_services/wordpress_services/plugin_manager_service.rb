module ContainerServices::WordpressServices
  ##
  # List plugins for a wordpress site
  #
  # [{"name"=>"akismet", "status"=>"inactive", "update"=>"none", "version"=>"5.1"},
  #    {"name"=>"hello", "status"=>"inactive", "update"=>"none", "version"=>"1.7.2"},
  #    {"name"=>"cstacks-config", "status"=>"must-use", "update"=>"none", "version"=>"0.1.0"}]
  #
  class PluginManagerService

    attr_reader :service,
                :plugins,
                :errors

    def initialize(service)
      @service = service
      @errors = []
      @plugins = []
      load_plugins
    end

    ##
    # Install a plugin
    # args: { plugin: Name or URL, version: String and optional, force: Boolean (default false), activate: Boolean (default is true) }
    # @param [ActionController::Parameters,Hash,nil] args
    def install!(args = {})
      args = args.to_h if args.respond_to?(:permitted)
      plugin = args[:plugin]

      unless args[:force]
        existing_plugins = plugins.collect {|i| i['name']}
        if existing_plugins.include?(args[:plugin])
          return true
        end
      end

      return install_ocp! if plugin == "objectcachepro"
      if plugin == 'extendify' && !Setting.wordpress_extendify_license.blank?
        return install_extendify_partner!
      end
      version = args[:version].blank? ? nil : args[:version]
      force = args[:force] ? args[:force] : false
      activate = args[:activate].nil? ? true : args[:activate]
      c = %W(install #{plugin})
      c << "--version=#{version}" if version
      c << "--force" if force
      c << "--activate" if activate
      if plugin_exec! c
        load_plugins
      end
    end

    # Activate a plugin that's already installed
    def activate!(plugin_name)
      c = %W(activate #{plugin_name})
      if plugin_exec! c
        load_plugins
      end
    end

    # Deactivate a plugin
    def deactivate!(plugin_name)
      c = %W(deactivate #{plugin_name})
      if plugin_exec! c
        load_plugins
      end
    end

    ##
    # Delete a plugin
    # args: { plugin: String, deactivate: Default is true, skip_delete: whether or not to delete files on disk }
    # @param [String] plugin
    # @param [ActionController::Parameters,Hash,nil] args
    def delete!(plugin, args = {})
      args = args.to_h if args.respond_to?(:permitted)
      deactivate  = args[:deactivate].nil? ? true : args[:deactivate]
      skip_delete = args[:skip_delete].nil? ? false : args[:skip_delete]
      c = %W(uninstall #{plugin})
      c << "--deactivate" if deactivate
      c << "--skip_delete" if skip_delete
      if plugin_exec! c
        load_plugins
      end
    end

    ##
    # AutoUpdates
    # @param [String] plugin
    # @param [Boolean] enable
    def auto_update_set!(plugin, enable = true)
      c = if enable
            %W(auto-updates enable #{plugin})
          else
            %W(auto-updates disable #{plugin})
          end
      if plugin_exec! c
        load_plugins
      end
    end

    # Return a list of auto update statuses
    # @return [Array] `["akismet", "hello"]`
    def auto_updates
      return [] if @service.nil?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        @errors << "No active container found"
        return []
      end
      c = if container.is_a?(Deployment::Container)
            %w(sudo -u www-data wp plugin auto-updates status --all --skip-plugins --skip-themes --quiet --field=name --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp plugin auto-updates status --all --skip-plugins --skip-themes --quiet --field=name --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      data = container.container_exec!(c, nil, 20)
      if data[:exit_code] == 0
        data[:response].blank? ? [] : data[:response].split("\n").map {|i| i.strip}
      else
        []
      end
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      []
    rescue => e
      ExceptionAlertService.new(e, '779f0d0f5e41d50e').perform
      @errors << e.message
      []
    end

    ##
    # Validate plugin checksums are correct
    #
    # * Returns empty array If everything is fine
    # * Returns [ { error: "message" } ] If error
    # * Returns [{"plugin_name"=>"akismet", "file"=>"wrapper.php", "message"=>"Checksum does not match"}] on found. One hash obj per file.
    #
    def validate_checksums!
      return [] if @service.nil?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        @errors << "No active container found"
        return []
      end
      c = if container.is_a?(Deployment::Container)
            %w(sudo -u www-data wp plugin verify-checksums --all --json --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp plugin verify-checksums --all --json --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      data = container.container_exec!(c, nil, 20)
      if data[:exit_code] == 0
        d = data[:response].is_a?(Array) ? data[:response][0] : data[:response]
        d = d.is_a?(Array) ? d[0] : d
        rsp = parse_wp_json d
        rsp = parse_wp_json "#{data[:response].split("]")[0]}]" if rsp.nil?
        rsp
      else
        []
      end
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      [{error: "Timeout"}]
    rescue => e
      ExceptionAlertService.new(e, '0de5d09acde41fa3').perform
      @errors << e.message
      [{error: e.message}]
    end

    private

    ##
    # Install Extendify Partner File
    def install_extendify_partner!
      return false if @service.nil?
      container = @service.sftp_containers.first
      if container.nil?
        @errors << "No active container found"
        return false
      end
      license_key = Setting.wordpress_extendify_license
      provider_name = Setting.wordpress_extendify_provider
      logo = Setting.wordpress_extendify_logo.gsub("/","\\/")
      bgcolor = Setting.wordpress_extendify_bgcolor
      fgcolor = Setting.wordpress_extendify_fgcolor
      if license_key.blank? || provider_name.blank?
        @errors << "Missing license"
        return false
      end
      c = %W(sudo -u sftpuser /usr/local/bin/install_extendify --license #{license_key} --name #{provider_name} --logo #{logo} --bgcolor #{bgcolor} --fgcolor #{fgcolor} --path #{container.service_files_path(service)}/wordpress/html/wordpress)
      data = container.container_exec!(c, nil, 60)
      unless data[:exit_code] == 0
        @errors << data[:response]
      end
      data[:exit_code] == 0
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      false
    rescue => e
      ExceptionAlertService.new(e, '1d125f4d72d7a660').perform
      @errors << e.message
      false
    end


    ##
    # Installs ObjectCachePro
    #
    # Requires a license be added into Settings
    #
    def install_ocp!
      return false if @service.nil?
      container = @service.sftp_containers.first
      if container.nil?
        @errors << "No active container found"
        return false
      end
      s = Setting.wordpress_ocp_token
      return false if s.blank?

      redis_containers = @service.deployment.services.where(container_images: {role: 'redis'}).joins(:container_image)
      if redis_containers.empty? || redis_containers.first.containers.empty?
        @errors << "Missing redis container"
        return false
      end
      redis_ip = redis_containers.first.containers.first.local_ip
      if redis_ip.blank?
        @errors << "Redis container does not have an ip address"
        return false
      end

      c = %W(sudo -u sftpuser /usr/local/bin/install_ocp --token #{s} --redis #{redis_ip} --path #{container.service_files_path(service)}/wordpress/html/wordpress)
      data = container.container_exec!(c, nil, 20)
      data[:exit_code] == 0
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      false
    rescue => e
      ExceptionAlertService.new(e, '1d125f4d72d7a660').perform
      @errors << e.message
      false
    end

    def plugin_exec!(cmd = [])
      return false if @service.nil?
      return false if cmd.empty?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        @errors << "No active container found"
        return []
      end
      c = if container.is_a?(Deployment::Container)
            %w(sudo -u www-data wp plugin)
          else
            %W(sudo -u sftpuser wp plugin)
          end
      cmd.each do |i|
        c << i
      end
      if container.is_a?(Deployment::Container)
        c << "--path=/var/www/html/wordpress"
      else
        c << "--path=#{container.service_files_path(service)}/wordpress/html/wordpress"
      end
      data = container.container_exec!(c, nil, 60)
      data[:exit_code] == 0
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      false
    rescue => e
      ExceptionAlertService.new(e, '779f0d0f5e41d50e').perform
      @errors << e.message
      false
    end

    def load_plugins
      return if @service.nil?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        errors << "No active container found"
        return []
      end
      c = if container.is_a?(Deployment::Container)
            %W(sudo -u www-data wp plugin list --json --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp plugin list --json --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      data = container.container_exec!(c, nil, 20)
      d = data[:response].is_a?(Array) ? data[:response][0] : data[:response]
      d = d.is_a?(Array) ? d[0] : d
      rsp = parse_wp_json d
      rsp = parse_wp_json "#{data[:response].split("]")[0]}]" if rsp.nil?
      rsp = rsp.map { |i| ActiveSupport::HashWithIndifferentAccess.new i } unless rsp.nil? || rsp.empty?
      @plugins = rsp.nil? ? [] : rsp
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      nil
    rescue => e
      ExceptionAlertService.new(e, '63babf59ec4a5b8a').perform
      @errors << e.message
      nil
    end

    def parse_wp_json(data)
      Oj.load data
    rescue JSON::ParserError
      nil
    end

  end
end
