module ContainerServices::WordpressServices
  class SiteManagerService

    attr_reader :service,
                :version,
                :errors

    # @param [Deployment::ContainerService,nil] service
    def initialize(service)
      @service = service
      @errors = []
      @version = nil
      load_version!
    end

    ##
    # Returns a wp profile report
    #
    # Example:
    # [ {"hook"=>"wp_footer:after",
    #   "callback_count"=>0,
    #   "time"=>1.7881393432617188e-05,
    #   "query_time"=>0,
    #   "query_count"=>0,
    #   "cache_ratio"=>nil,
    #   "cache_hits"=>0,
    #   "cache_misses"=>0,
    #   "request_time"=>0,
    #   "request_count"=>0}
    # ]
    #
    def profile
      return [] if @service.nil?
      container = @service.sftp_containers.first
      if container.nil?
        @errors << "No active container found"
        return [{error: "No active container found"}]
      end
      c = %W(sudo -u sftpuser wp profile stage --all --json --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
      data = container.container_exec!(c, nil, 20)
      if data[:exit_code] == 0
        d = data[:response].is_a?(Array) ? data[:response][0] : data[:response]
        d = d.is_a?(Array) ? d[0] : d
        rsp = parse_wp_json d
        rsp = parse_wp_json "#{data[:response].split("]")[0]}]" if rsp.nil?
        rsp
      else
        [ error: data[:response] ]
      end
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      [{error: "Timeout"}]
    rescue => e
      ExceptionAlertService.new(e, '0fbc8188aa5662d3').perform
      @errors << e.message
      [{error: e.message}]
    end

    # @return [Hash] `{ option_name: option_value }`
    def load_details!
      return if @service.nil?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        errors << "No active container found"
        return {}
      end
      c = if container.is_a?(Deployment::Container)
            %W(sudo -u www-data wp option list --json --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp option list --json --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      data = container.container_exec!(c, nil, 20)
      if data[:exit_code] == 0
        d = data[:response].is_a?(Array) ? data[:response][0] : data[:response]
        d = d.is_a?(Array) ? d[0] : d
        rsp = parse_wp_json d
        rsp = parse_wp_json "#{data[:response].split("]")[0]}]" if rsp.nil?
        result = rsp.select do |i|
          %w(
            home
            siteurl
            blogname
            blogdescription
            users_can_register
            admin_email
            template
            stylesheet
            use_trackback
            blog_public
            site_icon
          ).include? i['option_name']
        end
        result.map { |arr| { arr['option_name'] => arr['option_value'] } }
      else
        {}
      end
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      {}
    rescue => e
      ExceptionAlertService.new(e, '37a00413675125cc').perform
      @errors << e.message
      {}
    end

    ##
    # Update any option value
    def update_option!(option_name, option_value)
      return false if @service.nil?
      return false if option_name.blank?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        @errors << "No active container found"
        return []
      end
      c = if container.is_a?(Deployment::Container)
            %W(sudo -u www-data wp option update #{option_name} #{option_value} --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp option update #{option_name} #{option_value} --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      data = container.container_exec!(c, nil, 20)
      data[:exit_code] == 0
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      false
    rescue => e
      ExceptionAlertService.new(e, '2d5053f08445a302').perform
      @errors << e.message
      false
    end

    ##
    # Set Site Domain
    # @param [String] domain | "https://mydomain.com"
    # @param [Boolean] search_replace
    def update_site_url!(domain, search_replace = true)
      return false if @service.nil?
      return false if domain.blank?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        @errors << "No active container found"
        return []
      end
      current_site_url = nil
      # Get current siteurl
      if search_replace

        current_url_cmd = if container.is_a?(Deployment::Container)
                        %W(sudo -u www-data wp option get siteurl --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
                      else
                        %W(sudo -u sftpuser wp option get siteurl --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
                      end
        current_url_result = container.container_exec!(current_url_cmd, nil, 20)
        unless current_url_result[:exit_code] == 0
          # Error
          return false
        end
        current_site_url = current_url_result[:response]
      end

      siteurl_cmd = if container.is_a?(Deployment::Container)
            %W(sudo -u www-data wp option update siteurl #{domain} --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp option update siteurl #{domain} --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      siteurl = container.container_exec!(siteurl_cmd, nil, 20)
      unless siteurl[:exit_code] == 0
        # Error
        return false
      end

      home_cmd = if container.is_a?(Deployment::Container)
                      %W(sudo -u www-data wp option update home #{domain} --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
                    else
                      %W(sudo -u sftpuser wp option update home #{domain} --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
                    end
      home_result = container.container_exec!(home_cmd, nil, 20)
      unless home_result[:exit_code] == 0
        # Error
        return false
      end

      return true unless search_replace || current_site_url.blank?

      search_replace_cmd = if container.is_a?(Deployment::Container)
                   %W(sudo -u www-data wp search-replace #{current_site_url} #{domain} --report-changed-only --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
                 else
                   %W(sudo -u sftpuser wp search-replace #{current_site_url} #{domain} --report-changed-only --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
                 end
      search_replace_result = container.container_exec!(search_replace_cmd, nil, 600)
      search_replace_result[:exit_code] == 0
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      false
    rescue => e
      ExceptionAlertService.new(e, 'd60e76771e57c033').perform
      @errors << e.message
      false
    end

    def verify_checksum!
      return if @service.nil?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        errors << "No active container found"
        return []
      end
      c = if container.is_a?(Deployment::Container)
            %W(sudo -u www-data wp core verify-checksums --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp core verify-checksums --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      data = container.container_exec!(c, nil, 20)
      data[:exit_code] == 0
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      nil
    rescue => e
      ExceptionAlertService.new(e, '21c06c8c0935acbd').perform
      @errors << e.message
      nil
    end

    private

    def load_version!
      return if @service.nil?
      container = @service.sftp_containers.first
      container = @service.containers.active.first if container.nil?
      if container.nil?
        errors << "No active container found"
        return []
      end
      c = if container.is_a?(Deployment::Container)
            %W(sudo -u www-data wp core version --skip-plugins --skip-themes --quiet --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp core version --skip-plugins --skip-themes --quiet --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      data = container.container_exec!(c, nil, 20)
      if data[:exit_code] == 0
        @version = data[:response].strip
      else
        nil
      end
    rescue Docker::Error::TimeoutError
      @errors << "Timeout reached while attempting to connect to the container."
      nil
    rescue => e
      ExceptionAlertService.new(e, '37a00413675125cc').perform
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
