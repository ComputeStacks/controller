module Networks
  module IngressRulesHelper

    # @param [Deployment::ContainerService] i
    def edit_ingress_rule_path(i)
      return nil if i.container_service.nil?
      "#{ingress_rule_path(i)}/edit"
    end

    # @param [Deployment::ContainerService] i
    def ingress_rule_path(i)
      return nil if i.container_service.nil?
      "/container_services/#{i.container_service.id}/ingress/#{i.id}"
    end

    # Activate or DeActivate Public Port
    #
    # ingress_rule can be either:
    # * ContainerImage::IngressParam
    # * Network::IngressRule
    def ingress_toggle_btn(ingress_rule)
      return '80, 443' if ingress_rule.proto == 'http'
      if ingress_rule.public_port.zero?
        link_to t('actions.activate'), "#{ingress_rule_path(ingress_rule)}/toggle_nat", method: :post, data: {confirm: 'Are you sure? This will publicly expose this endpoint.'}
      elsif ingress_rule.public_port > 0
        link_to ingress_rule.public_network? ? "Deactivate" : ingress_rule.public_port, "#{ingress_rule_path(ingress_rule)}/toggle_nat", method: :post, data: {confirm: 'Are you sure? This will disable public access and reset this NAT port.'}
      end
    end

    # ingress_rule can be either:
    # * ContainerImage::IngressParam
    # * Network::IngressRule
    def ingress_backend_proto(ingress_rule)
      case ingress_rule.proto
      when 'http'
        ingress_rule.backend_ssl ? 'http &rarr; https'.html_safe : 'http'
      when 'tcp'
        ingress_rule.backend_ssl ? 'tcp &rarr; tcp+tls'.html_safe : 'tcp'
      when 'tls'
        ingress_rule.backend_ssl ? 'tcp+tls' : 'tcp+tls &rarr; tcp'.html_safe
      when 'udp'
        'udp'
      else
        '...'
      end
    end

    def ingress_domain_proto(domain)
      ingress_rule = domain.ingress_rule
      return '...' if ingress_rule.nil?
      lb_name = ingress_rule.internal_load_balancer.nil? ? 'LoadBalancer' : ingress_rule.internal_load_balancer.label
      case ingress_rule.proto
      when 'http'
        if domain.force_ssl?
          # SSL -> LB -> SSL vs SSL -> LB -> HTTP
          ingress_rule.backend_ssl ? 'https' : %Q(<span title="Internet &rarr; #{lb_name} &rarr; #{domain.container_service.name}">https &rarr; http</span>).html_safe
        else
          ingress_rule.backend_ssl ? %Q(<span title="Internet &rarr; #{lb_name} &rarr; #{domain.container_service.name}">http &rarr; https</span>).html_safe : 'http'
        end
      when 'tcp'
        ingress_rule.backend_ssl ? %Q(<span title="Internet &rarr; #{lb_name} &rarr; #{domain.container_service.name}">tcp &rarr; tcp+tls</span>).html_safe : 'tcp'
      when 'tls'
        ingress_rule.backend_ssl ? 'tcp+tls' : %Q(<span title="Internet &rarr; #{lb_name} &rarr; #{domain.container_service.name}">tcp+tls &rarr; tcp</span>).html_safe
      when 'udp'
        'udp'
      else
        '...'
      end
    end

    def ingress_load_balancer(ingress)
      if ingress.container_service
        if ingress.proto == 'udp' && ingress.external_access && ingress.load_balancer_rule.nil?
          return ingress.container_service.nodes.pluck(:primary_ip).map {|i| "<code>#{i}</code>"}.join(', ').html_safe
        end
        if ingress.external_access && ingress.load_balancer_rule.nil?
          return ingress.container_service.load_balancer.nil? ? 'Global' : "<code>#{ingress.container_service.load_balancer.public_ip}</code>".html_safe
        end
      end
      if ingress.external_access && ingress.internal_load_balancer
        return link_to(ingress.internal_load_balancer.label, "#{container_service_path(ingress.internal_load_balancer)}")
      end
      'None'
    end

    def ingress_attached_service(ingress)
      if ingress.container_service
        link_to(ingress.container_service.label, "#{container_service_path(ingress.container_service)}")
      elsif ingress.sftp_container
        'sftp container'
      else
        '...'
      end
    end

    # @param [Deployment::ContainerService] service
    def has_ingress_connect_helper?(service)
      %w(mysql).include? service.container_image.role
    end

    # @param [Deployment::ContainerService] service
    def ingress_remote_connect_helper(service)
      return '' unless service.ingress_rules.where(external_access: true).exists?
      cmd = []
      lb = service.load_balancer
      lb = service.region.load_balancer if lb.nil?
      return '' if lb.nil?
      temp_public_ip = service.containers.first&.ip_addr
      service.ingress_rules.each do |ingress|
        case service.container_image.role
        when 'mysql'
          if ingress.port == 3306
            cmd << %Q(mysql -u root -h #{temp_public_ip} -P #{ingress.port_nat} -p)
          end
        else
          next
        end
      end
      cmd.empty? ? '' : cmd.join("\n")
    end

  end
end
