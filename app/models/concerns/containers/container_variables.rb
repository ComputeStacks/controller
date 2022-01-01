module Containers
  module ContainerVariables
    extend ActiveSupport::Concern

    def var_lookup(var)
      var = var.split(".")
      param = nil
      case var.first
      when "region"
        case var[1]
        when "endpoint"
          case var[2]
          when "api"
            param = {'type' => 'raw', 'value' => "https://#{Setting.hostname}/api"}
          end
        end
      when "build"
        case var[1]
        when "settings"
          v = self.service.setting_params.find_by(name: var[2])
          return nil if v.nil?
          param = {'type' => 'raw', 'value' => v.decrypted_value}
        when "self"
          # ports are deprecated
          the_port = service.ingress_rules.first&.port
          case var[2]
          when "name"
            param = {'type' => "raw", 'value' => self.name}
          when "name_short"
            param = {'type' => "raw", 'value' => self.name.gsub("-","").gsub("_","")}
          when 'service_name'
            param = { 'type' => 'raw', 'value' => self.service.name }
          when 'service_name_short'
            param = { 'type' => 'raw', 'value' => self.service.name.gsub("-","").gsub("_","") }
          when "local_dns"
            param = {'type' => "raw", 'value' => self.local_ip}
          when 'ip'
            param = {'type' => "raw", 'value' => self.local_ip}
          when 'ip_with_port'
            return nil if the_port.nil?
            param = {'type' => "raw", 'value' => "#{self.local_ip}:#{the_port}"}
          when 'port'
            return nil if the_port.nil?
            param = {'type' => "raw", 'value' => the_port}
          when "project_id"
            param = {'type' => 'raw', 'value' => self.deployment&.id}
          when "default_domain"
            # domains = self.find_params("domains")
            # if domains.nil?
            #   the_domain = "#{self.service.name}.#{Deployment::ContainerDomain.sys_domain(self.region).first}"
            # else
            #   the_domain = domains.value.first
            # end
            # the_domain = "#{self.service.name}.#{Deployment::ContainerDomain.sys_domain(self.region).first}"
            param = {'type' => 'raw', 'value' => service.default_domain}
          when "default_domain_with_proto"
            param = {'type' => 'raw', 'value' => "https://#{service.default_domain}"}
          end
        end
      when "dep"
        # Dependency
        dep_role = var[1]
        dep_container = nil
        dep_service = nil
        # Find the correct container by its role.
        self.service.service_resources.each do |c|
          if c.container_image.role == dep_role
            dep_service = c
            dep_container = c.containers.first
            break
          end
        end
        return nil if dep_container.nil?
        if var[2] == "parameters"
          param_key = var[3]
          param_option_key = var[4]
          dep_params = case param_key
                       when 'settings'
                         dep_service.setting_params.find_by(name: param_option_key)
                       when 'env'
                         dep_service.env_params.find_by(name: param_option_key)
                       end
          if dep_params.nil?
            # l = self.event_logs.create(
            #   status: 'alert',
            #   notice: true,
            #   locale: 'container.errors.general_provision',
            #   state_reason: "Unable to locate param with key: #{param_key}",
            #   locale_keys: {
            #     'label' => self.service.label,
            #     'container' => self.name
            #   },
            #   event_code: '81f5c0c2da70a356'
            # )
            # l.deployments << self.deployment if self.deployment
            # l.users << self.user if self.user
            return nil
          else
            param = dep_params.nil? ? nil : {'type' => 'raw', 'value' => dep_params.decrypted_value}
            if param.nil?
              # l = self.event_logs.create(
              #   status: 'alert',
              #   notice: true,
              #   locale: 'container.errors.general_provision',
              #   state_reason: "Unable to locate param.",
              #   locale_keys: {
              #     'label' => self.service.label,
              #     'container' => self.name
              #   },
              #   event_code: 'a1b3579d0b0b916d'
              # )
              # l.event_details.create!(data: "Key: #{param_option_key}\nVariable: #{var}", event_code: 'a1b3579d0b0b916d')
              # l.deployments << self.deployment if self.deployment
              # l.users << self.user if self.user
              return nil
            end # end param.nil?
          end # END dep_param
        else
          dep_host_ip = dep_container.local_ip
          # ports are deprecated
          external_port = dep_container.service.ingress_rules.first&.port
          case var[2]
          when "host" # No longer used. Keep for backwards compatability
            case var[3]
            when "ip"
              param = {'type' => "raw", 'value' => dep_host_ip}
            when "ip_with_port"
              param = {'type' => "raw", 'value' => "#{dep_host_ip}:#{external_port}"}
            when "port"
              param = {'type' => "raw", 'value' => external_port}
            when "local_dns_with_port"
              param = {'type' => "raw", 'value' => "#{dep_host_ip}:#{external_port}"}
            when "local_dns"
              param = {'type' => "raw", 'value' => dep_host_ip}
            end
          when "self" # New version
            case var[3]
            when "ip"
              param = {'type' => "raw", 'value' => dep_host_ip}
            when "ip_with_port"
              param = {'type' => "raw", 'value' => "#{dep_host_ip}:#{external_port}"}
            when "port"
              param = {'type' => "raw", 'value' => external_port}
            when "local_dns_with_port"
              param = {'type' => "raw", 'value' => "#{dep_host_ip}:#{external_port}"}
            when "local_dns"
              param = {'type' => "raw", 'value' => dep_host_ip}
            when "project_id"
              param = {'type' => 'raw', 'value' => dep_service&.deployment&.id}
            end # END var[3]
          end # END var[2]
        end # END var[2] == parameters
      end # END case var.first
      if param
        case param['type']
        when "password"
          return Secret.decrypt!(param['value'])
        when "variable"
          return self.var_lookup(param['reference'])
        when "port"
          return param['options']['external']
        when "raw", "string", "static"
          return param['value']
        when 'integer'
          return param['value'].to_i
        end
      end
    end # END var_lookup

  end
end
