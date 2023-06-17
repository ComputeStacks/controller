module Containers
  module ContainerNetworking
    extend ActiveSupport::Concern

    included do
      after_create_commit :set_ip_address!
    end

    def ip_addr
      node&.public_ip
    end

    def public_ip
      load_balancer.nil? ? ip_addr : load_balancer.public_ip
    end

    def local_ip
      ip_address&.ipaddr
    end

    def api_ingress_rules
      r = []
      service.ingress_rules.each do |i|
        rule = Rabl::Renderer.new('api/networks/ingress_rules/show', i, view_path: 'app/views', format: 'hash').render[:ingress_rule]
        rule[:public_ip] = if !i.external_access
                             nil
                           elsif i.uses_iptables?
                             node&.public_ip
                           else
                             public_ip
                           end
        r << rule
      end
      r
    rescue => e
      ExceptionAlertService.new(e, 'd49644ee4f1d51ae', current_audit&.user).perform
      []
    end

    # private

    # provision ip address
    def set_ip_address!
      return false if region.nil?

      net = if deployment.private_network
              deployment.private_network
            elsif region.has_clustered_networking?
              region.networks.clustered.shared.active.first
            else
              nil
            end

      if net.nil?
        l = event_logs.create!(
          status: 'alert',
          notice: true,
          locale: 'deployment.errors.fatal',
          event_code: '428c027fdfec4f7d',
          state_reason: 'Missing network'
        )
        l.deployments << deployment if deployment
        l.users << user if user
      else
        if ip_address.nil?
          if generate_container_ip!
            reload_ip_address
            return !ip_address.ipaddr.blank?
          else
            l = event_logs.create!(
              status: 'alert',
              notice: true,
              locale: 'deployment.errors.fatal',
              event_code: 'f29a81e15c68eabf',
              state_reason: 'missing ip address'
            )
            l.event_details.create!(data: "Error generating local IP for #{name}.", event_code: 'f29a81e15c68eabf')
            l.deployments << deployment if deployment
            l.users << user if user
            false
          end
        else
          true
        end
      end
    rescue => e
      ExceptionAlertService.new(e, '851ef652010566f0', current_audit&.user).perform
      l = event_logs.create!(
        status: 'alert',
        notice: true,
        locale: 'deployment.errors.fatal',
        event_code: '851ef652010566f0',
        state_reason: 'fatal error with ip address'
      )
      l.event_details.create!(data: "Fatal error generating local IP for #{name}.\n\n #{e.message}", event_code: '851ef652010566f0')
      l.deployments << deployment if deployment
      l.users << user if user
      nil
    end

    def generate_container_ip!
      net = if deployment.private_network
              deployment.private_network
            elsif region.has_clustered_networking?
              region.networks.clustered.shared.active.first
            else
              nil
            end

      # For shared networks (calico), find the least utilized network.
      if deployment.private_network.nil?
        region.networks.clustered.shared.active.each do |n|
          next if net == n
          range = n.subnet.to_range
          next if range.count - n.addresses.count < 2
          net = n if n.addresses.count < net.addresses.count
        end
      end

      if net.nil?
        l = event_logs.create!(
          status: 'alert',
          notice: true,
          locale: 'deployment.errors.fatal',
          event_code: '266d41d10b1d13c6',
          state_reason: 'fatal error with ip address'
        )
        l.event_details.create!(data: "Fatal error generating local IP for #{name}.\n\n Unable to locate available network.", event_code: '266d41d10b1d13c6')
        l.deployments << deployment if deployment
        l.users << user if user
        return false
      end

      ##
      # We could be building multiple containers at the same time, and could end up assigning the same IP. This will keep trying if that fails.
      count = 1
      need_ip = true
      while count < 5 && need_ip do
        reload
        reload_ip_address
        unless ip_address.nil?
          need_ip = false
          break
        end
        count += 1
        begin
          if create_ip_address!(network: net)
            need_ip = false
            break
          else
            sleep(1)
            next
          end
        rescue ActiveRecord::RecordNotUnique => e
          ExceptionAlertService.new(e, 'c7ed2aedc5636c25', current_audit&.user).perform if count > 2
          sleep(1)
          next
        rescue PG::UniqueViolation => e
          ExceptionAlertService.new(e, '4ed5964112e50302', current_audit&.user).perform if count > 2
          sleep(1)
          next
        end
      end
      !need_ip
    end

  end
end
