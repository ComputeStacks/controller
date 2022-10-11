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
      container = service.containers.active.first
      if container.nil?
        errors << "No active container found"
        return []
      end
      c = %W(/usr/local/bin/wp user list --role=administrator --json --path=/var/www/html/wordpress --allow-root)
      data = container.container_exec!(c, nil, 20)

      # wp-cli will add non-json error messages to the output when there is a problem with an installation.
      # This will attempt to recover from that and parse out the original json.
      rsp = parse_wp_json data[:response]
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
