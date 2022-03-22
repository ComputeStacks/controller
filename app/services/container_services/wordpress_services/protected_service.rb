module ContainerServices::WordpressServices
  ##
  # Enable or Disable http basic auth in OpenLiteSpeed
  class ProtectedService

    attr_accessor :service,
                  :container,
                  :username,
                  :password,
                  :event,
                  :errors

    # @param [Deployment::ContainerService] service
    # @param [Audit] audit
    def initialize(service, p = nil)
      self.service = service
      self.errors = []
      self.password = p.nil? ? SecureRandom.urlsafe_base64(12) : p
      self.username = "wp"
      self.container = service.nil? ? nil : service.containers.active.first
      if container.nil?
        errors << "No active container found"
      end
    end

    def enabled?
      c = ["/bin/sh", "-c", "if [ -f /usr/local/lsws/conf/vhosts/Wordpress/.protect_enabled ]; then echo 'yes'; else echo 'no'; fi"]
      container.container_exec!(c, nil, 30).strip == 'yes'
    rescue => e
      ExceptionAlertService.new(e, 'b457f57908b7e09d').perform
      errors << e.message
      false
    end

    def enable!
      if event.nil?
        errors << "Missing event object"
        return false
      end
      event.start!
      c = ["/bin/sh", "-c", %Q(PW=$(openssl passwd -apr1 "#{password}"); echo "#{username}:$PW" > /usr/local/lsws/conf/vhosts/Wordpress/htpasswd && touch /usr/local/lsws/conf/vhosts/Wordpress/.protect_enabled && sed -i '/context \\/ /a realm protected' /usr/local/lsws/conf/vhosts/Wordpress/vhconf.conf)]
      d = container.container_exec!(c, nil, 30)
      if d.blank?
        if service.secrets.where(key_name: "protected_mode_pw").exists?
          service.secrets.find_by(key_name: "protected_mode_pw").update data: password
        else
          service.secrets.create!(key_name: "protected_mode_pw", data: password)
        end
        ContainerWorkers::ContainerExecWorker.perform_async container.to_global_id.uri, event.to_global_id.uri, ["/bin/sh", "-c", "/usr/local/lsws/bin/lswsctrl reload"]
        return true
      end
      errors << d
      event.event_details.create!(data: d, event_code: "27611d79ffaa1ff7")
      event.fail! "Error"
      false
    rescue => e
      ExceptionAlertService.new(e, '9be5f5080333a5b7').perform
      errors << e.message
      false
    end

    def disable!
      if event.nil?
        errors << "Missing event object"
        return false
      end
      event.start!
      c = ["/bin/sh", "-c", "if [ -f /usr/local/lsws/conf/vhosts/Wordpress/htpasswd ]; then rm /usr/local/lsws/conf/vhosts/Wordpress/htpasswd; fi && if [ -f /usr/local/lsws/conf/vhosts/Wordpress/.protect_enabled ]; then rm /usr/local/lsws/conf/vhosts/Wordpress/.protect_enabled; fi && sed -i '/realm protected$/d' /usr/local/lsws/conf/vhosts/Wordpress/vhconf.conf"]
      d = container.container_exec!(c, nil, 10)
      if d.blank?
        ContainerWorkers::ContainerExecWorker.perform_async container.to_global_id.uri, event.to_global_id.uri, ["/bin/sh", "-c", "/usr/local/lsws/bin/lswsctrl reload"]
        return true
      end
      errors << d
      event.event_details.create!(data: d, event_code: "8f9c5ac4bdfdca18")
      event.fail! "Error"
      false
    rescue => e
      ExceptionAlertService.new(e, 'a1366a42f5fe438c').perform
      errors << e.message
      false
    end

  end
end
