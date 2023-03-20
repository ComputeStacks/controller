module ContainerServices::WordpressServices
  class UserService

    attr_accessor :service,
                  :errors

    # @param [Deployment::ContainerService] service
    def initialize(service)
      self.service = service
      self.errors = []
    end

    ##
    # List all admin users
    #
    #     [
    #       {
    #         "ID"=>1,
    #         "user_login"=>"admin",
    #         "display_name"=>"admin",
    #         "user_email"=>"user@example.com",
    #         "user_registered"=>"2022-03-20 08:48:11",
    #         "roles"=>"administrator"
    #       }
    #     ]
    #
    def users
      # Try to use the sftp container, which is generally less susceptible to issues with the wordpress installation.
      container = service.sftp_containers.first
      container = service.containers.active.first if container.nil?
      if container.nil?
        errors << "No active container found"
        return []
      end
      c = if container.is_a?(Deployment::Container)
            %W(sudo -u www-data wp user list --role=administrator --json --path=/var/www/html/wordpress)
          else
            %W(sudo -u sftpuser wp user list --role=administrator --json --path=#{container.service_files_path(service)}/wordpress/html/wordpress)
          end
      data = container.container_exec!(c, nil, 20)

      # wp-cli will add non-json error messages to the output when there is a problem with an installation.
      # This will attempt to recover from that and parse out the original json.
      d = data[:response].is_a?(Array) ? data[:response][0] : data[:response]
      d = d.is_a?(Array) ? d[0] : d
      rsp = parse_wp_json d
      rsp = parse_wp_json "#{data[:response].split("]")[0]}]" if rsp.nil?
      rsp.nil? ? [] : rsp
    rescue Docker::Error::TimeoutError
      self.errors << "Timeout reached while attempting to connect to the container."
      []
    rescue => e
      ExceptionAlertService.new(e, '3a77b977010bea95').perform
      self.errors << e.message
      []
    end

    private

    def parse_wp_json(data)
      Oj.load data
    rescue JSON::ParserError
      nil
    end

  end
end
