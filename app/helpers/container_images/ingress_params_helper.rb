module ContainerImages
  module IngressParamsHelper

    # @param [ContainerImage] image
    def container_image_ingress_params_path(image)
      return container_images_path if image.nil?
      "#{container_image_path(image)}/ingress_params"
    end

    # @param [ContainerImage] image
    def new_container_image_ingress_param_path(image)
      return container_images_path if image.nil?
      "#{container_image_ingress_params_path(image)}/new"
    end

    # @param [ContainerImage::IngressParam] ingress
    def edit_container_image_ingress_param_path(ingress)
      return container_images_path if ingress.nil?
      "#{container_image_ingress_param_path(ingress)}/edit"
    end

    # @param [ContainerImage::IngressParam] ingress
    def container_image_ingress_param_path(ingress)
      return container_images_path if ingress.nil?
      "#{container_image_path(ingress.container_image)}/ingress_params/#{ingress.id}"
    end

    def ingress_param_proto_options
      [
        %w[HTTP(S) http],
        %w(TCP tcp),
        %w[TCP+TLS tls],
        %w[UDP udp]
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

  end
end
