module ContainerServices
  module ServiceConfig
    extend ActiveSupport::Concern

    def available_vars
      vars = ContainerImage.system_vars
      setting_params.each do |i|
        vars << "build.settings.#{i.name}"
      end
      dependent_services.each do |i|
        i.setting_params.each do |ii|
          vars << "dep.#{i.container_image.role}.parameters.settings.#{ii.name}"
        end
        vars << "dep.#{i.container_image.role}.self.ip"
        vars << "dep.#{i.container_image.role}.self.default_domain"
        # vars << "dep.#{i.container_image.role}.self.ip_with_port"
        # vars << "dep.#{i.container_image.role}.self.port"
      end
      vars
    end

    ##
    # Ensure container has required dependencies
    #
    # This is an important check to ensure that when we go to build
    # the container config, we have the required dependencies
    # to generate any variables defined in the configuration.
    #
    # @see Containers::ContainerVariables#var_lookup
    #
    def init_link!
      current_links = self.service_resources
      matches_fulfilled = true
      self.container_image.dependencies.each do |i|
        is_met = false
        # Make sure we're not already linked
        current_links.each do |c|
          if i.id == c.container_image.id || i.role == c.container_image.role
            is_met = true
            break
          end
        end
        unless is_met
          matched = nil
          self.deployment.services.order(created_at: :desc).each do |dc|
            if dc.container_image.id == i.id || dc.container_image.role == i.role
              matched = dc
            end
          end
          if matched
            self.service_resources << matched
          else
            matches_fulfilled = false
            break
          end
        end # END unless is_met
      end # END self.container_images.dependencies.each
      matches_fulfilled
    end

    # List of settings used for api output and display purposes
    # This will include both local settings, and the settings of the custom load balancer
    def combined_settings
      return setting_params if internal_load_balancers.empty?
      setting_params + internal_load_balancers.map { |i| i.setting_params }.flatten
    end

    def gen_settings_config!(event, additional_params = {})
      success = true
      container_image.setting_params.each do |i|
        next if setting_params.where(parent_param: i).exists?
        sp = setting_params.new(
          name: i.name,
          label: i.label,
          param_type: i.param_type,
          parent_param: i,
          skip_metadata_refresh: true
        )
        case i.param_type
        when 'static'
          sp.value = additional_params.dig(sp.name, 'value') ? additional_params[sp.name]['value'] : i.value
        when 'password'
          pw = nil
          if additional_params.dig(sp.name, 'value')
            pw = additional_params[sp.name]['value']
          else
            pw = SecureRandom.urlsafe_base64(10).gsub("_", "").gsub("-", "")
            pw = pw + SecureRandom.random_number(100).to_s if pw.scan(/\d+/).first.nil?
          end
          sp.value = Secret.encrypt!(pw)
        else
          event.event_details.create!(
            data: "Unknown param type: #{i.param_type} for service #{name} (#{id})",
            event_code: 'f5e9a5643bafba5f'
          )
          event.container_services << self unless event.container_services.include?(self)
          event.deployments << deployment if deployment && !event.deployments.include?(deployment)
          next
        end
        unless sp.save
          event.event_details.create!(data: "Failed to generate setting for service: #{i.name}: #{sp.errors.full_messages.join(' ')}", event_code: 'ec75f3a877a0d0e3')
          event.container_services << self unless event.container_services.include?(self)
          event.deployments << deployment if deployment && !event.deployments.include?(deployment)
          success = false
        end
      end
      success
    rescue => e
      ExceptionAlertService.new(e, '236c68aa2e763842').perform
      if event
        event.event_details.create!(data: "Error building setting config for service: #{name}\n\n #{e.message}", event_code: '236c68aa2e763842')
        event.container_services << self unless event.container_services.include?(self)
        event.deployments << deployment if deployment && !event.deployments.include?(deployment)
      end
      false
    end

    def gen_env_config!(event)
      success = true
      container_image.env_params.each do |i|
        next if env_params.where(parent_param: i).exists?
        ep = env_params.new(
          name: i.name,
          label: i.label,
          param_type: i.param_type,
          value: i.value,
          parent_param: i,
          skip_metadata_refresh: true
        )
        unless ep.save
          event.event_details.create!(
            data: "Failed to generate environmental config for service: #{i.name}: #{ep.errors.full_messages.join(' ')}",
            event_code: '079899a441dae3f7'
          )
          event.container_services << self unless event.container_services.include?(self)
          event.deployments << deployment if deployment && !event.deployments.include?(deployment)
          success = false
        end
      end
      success
    rescue => e
      ExceptionAlertService.new(e, '6423245e9105c964').perform
      if event
        event.event_details.create!(data: "Error building environment config for service: #{name}\n\n #{e.message}", event_code: '6423245e9105c964')
        event.container_services << self unless event.container_services.include?(self)
        event.deployments << deployment if deployment && !event.deployments.include?(deployment)
      end
      false
    end

    ##
    # Generate static environmental parameters from a source service
    #
    # @param [Deployment::ContainerService] source
    # @param [EventLog] event
    def gen_cloned_config!(source, event)
      success = true
      source.env_params.where(param_type: 'static').each do |i|
        ep = env_params.new(
          name: i.name,
          label: i.label,
          param_type: i.param_type,
          value: i.value,
          parent_param: i.parent_param,
          skip_metadata_refresh: true
        )
        unless ep.save
          event.event_details.create!(
            data: "Failed to generate cloned environmental config for service: #{i.name}: #{ep.errors.full_messages.join(' ')}",
            event_code: '1be81a3f6c609cbd'
          )
          event.container_services << self unless event.container_services.include?(self)
          event.deployments << deployment if deployment && !event.deployments.include?(deployment)
          success = false
        end
      end
      success
    rescue => e
      ExceptionAlertService.new(e, '74a0bde929159a9c').perform
      if event
        event.event_details.create!(data: "Error building cloned environment config for service: #{name}\n\n #{e.message}", event_code: '74a0bde929159a9c')
        event.container_services << self unless event.container_services.include?(self)
        event.deployments << deployment if deployment && !event.deployments.include?(deployment)
      end
      false
    end

    def gen_ingress_rules!(event)
      success = true
      container_image.ingress_params.each do |i|
        next if ingress_rules.where(parent_param: i).exists?
        rule_proto = ( i.proto == 'http' && public_network? ) ? 'tcp' : i.proto
        pp = ingress_rules.new(
          parent_param: i,
          external_access: i.external_access,
          proto: rule_proto,
          port: i.port,
          backend_ssl: i.backend_ssl,
          tcp_proxy_opt: i.tcp_proxy_opt,
          tcp_lb: public_network? ? false : i.tcp_lb,
          sys_no_reload: true, # Don't reload the LB.
          skip_metadata_refresh: true,
          region: region
        )
        if i.load_balancer_rule
          lb_service = deployment.services.load_balancers.where("labels @> ?", {load_balancer_for: self.id}.to_json).first
          lb_ingress_rule = lb_service.nil? ? nil : lb_service.ingress_rules.where(parent_param: i.load_balancer_rule).first
          if lb_ingress_rule.nil?
            event.event_details.create!(data: "Failed to find internal load balancer for service: #{name}: Expected to find image (#{i.load_balancer_rule.container_image&.id})#{i.load_balancer_rule.container_image&.label}", event_code: 'bbe10febfb44f848')
            event.container_services << self unless event.container_services.include?(self)
            event.deployments << deployment if deployment && !event.deployments.include?(deployment)
            next
          end
          pp.load_balancer_rule = lb_ingress_rule
        end

        unless pp.save
          event.event_details.create!(data: "Failed to generate ingress rule for service: #{name}: #{pp.errors.full_messages.join(' ')}", event_code: '89e4a3e0d2fe439f')
          event.container_services << self unless event.container_services.include?(self)
          event.deployments << deployment if deployment && !event.deployments.include?(deployment)
          success = false
        end
      end
      success
    rescue => e
      ExceptionAlertService.new(e, '2480e9fa50103cd4').perform
      if event
        event.event_details.create!(data: "Error building ingress rules for service: #{name}\n\n #{e.message}", event_code: '2480e9fa50103cd4')
        event.container_services << self unless event.container_services.include?(self)
        event.deployments << deployment if deployment && !event.deployments.include?(deployment)
      end
      false
    end # END gen_ingress_rules!
  end
end
