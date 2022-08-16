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
    # @return [Array]
    def users
      container = service.containers.active.first
      if container.nil?
        errors << "No active container found"
        return []
      end
      c = %W(/usr/local/bin/wp user list --role=administrator --json --path=/var/www/html/wordpress --allow-root)
      data = container.container_exec!(c, nil, 15)
      Oj.load(data)
    rescue => e
      ExceptionAlertService.new(e, '3a77b977010bea95').perform
      self.errors << e.message
      []
    end

  end
end
