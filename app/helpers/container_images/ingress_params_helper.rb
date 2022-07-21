module ContainerImages
  module IngressParamsHelper

    def ingress_param_proto_options(rule = nil)
      rule_list = [
        %w[HTTP(S) http],
        %w(TCP tcp),
        %w[TCP+TLS tls],
        %w[UDP udp]
      ]
      return rule_list if rule.nil? || !rule.public_network?
      [
        %w(TCP tcp),
        %w(UDP udp)
      ]
    end

    def ingress_param_tcp_options
      [
        %w(none none),
        %w(send-proxy-v1 send-proxy),
        %w(send-proxy-v2 send-proxy-v2),
        %w(send-proxy-v2-ssl send-proxy-v2-ssl),
        %w(send-proxy-v2-ssl-cn send-proxy-v2-ssl-cn)
      ]
    end

    def ingress_param_load_balancer(ingress)
      if ingress.external_access && ingress.load_balancer_rule.nil?
        return 'Global' if ingress.proto == 'http'
        return ingress.tcp_lb ? 'Global' : 'None'
      end
      if ingress.external_access && ingress.internal_load_balancer
        return link_to(ingress.internal_load_balancer.label, container_image_path(ingress.internal_load_balancer))
      end
      'None'
    end

    def new_container_image_ingress_param_path(image)
      return nil if image.nil?
      "#{container_image_path(image)}/ingress_params/new"
    end

    def edit_container_image_ingress_param_path(ingress)
      return "/container_images" if ingress.nil?
      "#{container_image_ingress_param_path(ingress)}/edit"
    end

    def container_image_ingress_param_path(ingress)
      return "/container_images" if ingress.nil?
      "#{container_image_path(ingress.container_image)}/ingress_params/#{ingress.id}"
    end

  end
end
