module ContainerServices
  module ServiceIngress
    extend ActiveSupport::Concern

    included do
      has_many :ingress_rules, class_name: 'Network::IngressRule', dependent: :destroy
      has_many :domains, through: :ingress_rules, source: :container_domains
      has_many :load_balanced_rules, class_name: 'Network::IngressRule', dependent: :destroy

      belongs_to :load_balancer, optional: true

      # While it's a mant-to-one relationship, we should really only have 1 LB.
      has_many :internal_load_balancers, -> { distinct }, through: :ingress_rules, source: :internal_load_balancer
    end

    # public IP Addresses
    def public_network?
      region&.public_network?
    end

    def has_iptable_rules?
      tcp_ingress_rules.exists? || udp_ingress_rules.exists?
    end

    # Find public ip for this service
    # TODO: Determine what all uses this and possible combine this and `public_dns_records`.
    # Returns Array[]
    def public_ip
      if load_balancer
        # LoadBalancer
        [load_balancer.public_ip]
      elsif !internal_load_balancers.empty?
        # Deployment::ContainerService
        internal_load_balancers.map { |i| i.public_ip }.flatten
      else
        []
      end
    end

    # Display a list of records for the user
    def public_dns_records
      pub = []
      if load_balancer
        pub << load_balancer.public_ip
        load_balancer.ipaddrs.where(role: 'public').each do |i|
          addr = i.ip_addr.to_s
          pub << addr unless pub.include?(addr)
        end
      elsif !internal_load_balancers.empty?
        pub = internal_load_balancers.map { |i| i.public_dns_records }.flatten
      end
      pub
    end

    def allow_custom_domains?
      return false if is_load_balancer
      return false if container_image.service_container?
      ingress_rules.where(proto: 'http').exists?
    end

    def lb_tcp_ingress_rules
      ingress_rules.where(
        Arel.sql(
          "external_access = true AND port_nat > 0 AND (proto = 'tls' OR (proto = 'tcp' AND tcp_lb = true))"
        )
      )
    end

    def tcp_ingress_rules
      ingress_rules.where(
        Arel.sql(
          "external_access = true AND port_nat > 0 AND (proto = 'tls' OR (proto = 'tcp' AND tcp_lb = false))"
        )
      )
    end

    def udp_ingress_rules
      ingress_rules.where(
        Arel.sql(
          "external_access = true AND port_nat > 0 AND proto = 'udp'"
        )
      )
    end

  end
end
