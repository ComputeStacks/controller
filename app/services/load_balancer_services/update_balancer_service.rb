module LoadBalancerServices
  ##
  # Push updated configuration to load balancer
  #
  # @!attribute lb
  #   @return [LoadBalancer]
  class UpdateBalancerService

    attr_accessor :lb,
                  :errors

    # @param [LoadBalancer] lb
    def initialize(lb)
      self.lb = lb
      self.errors = []
    end

    # @return [Boolean]
    def perform
      if lb.nil?
        errors << "Unknown LoadBalancer (nil)"
        return false
      end

      unless lb.active?
        errors << "Load Balancer is not active"
        return false
      end

      # TODO: Test generating certs and configuration
      unless Rails.env.test?
        deploy_certificates!
        deploy_config!
      end

      lb.update_attribute :job_performed, Time.now
    end

    private

    def deploy_certificates!
      # Will remove this in the future once all deployments have this file.
      dhparam = File.read(Rails.root.to_s + "/lib/ffdhe2048.txt")
      lb.ext_ip.each do |i|
        is_node = Node.find_by("public_ip = ? OR primary_ip = ? OR hostname = ?", i, i, i)
        next if is_node && !is_node.online?
        ssh_port = is_node ? is_node.ssh_port : 22
        client = DockerSSH::Node.new("ssh://#{i}:#{ssh_port}", { key: "#{Rails.root}/#{ENV['CS_SSH_KEY']}" })
        # Cleanup unused certificates
        begin
          current_certs = client.client.exec!("ls #{lb.ext_cert_dir}")
        rescue => e
          # ExceptionAlertService.new(e, 'b2c3d0bdfc7f7fa5').perform
          SystemEvent.create!(
            message: "Failed to deploy load balancer certificates",
            log_level: 'warn',
            data: {
              'load_balancer' => lb.id,
              'errors' => e.message
            },
            event_code: 'b2c3d0bdfc7f7fa5'
          )
          next
        end
        cmds = []
        # Remove old certs.
        current_certs.split(/\n/).each do |ii|
          if ii == 'shared_cert.pem'
            # removed old shared cert
            cmds << "rm #{lb.ext_cert_dir}/shared_cert.pem"
            next
          end
          next unless ii[0..3] == 'cert' || ii[0..2] == 'le_'
          ssl_cert = if ii[0..3] == 'cert'
                       Deployment::Ssl.find_by(id: ii.split('cert').last.split('.').first.to_i)
                     elsif ii[0..2] == 'le_'
                       LetsEncrypt.find_by(id: ii.split('le_cert').last.split('.').first.to_i)
                     else
                       nil
                     end
          cmds << "rm #{lb.ext_cert_dir}/#{ii}" if ssl_cert.nil?
        end
        # Deploy new certificates
        lb.container_services.joins(:ssl_certificates).uniq.each do |s|
          s.ssl_certificates.each do |ssl|
            cert_name = "cert#{ssl.id}"
            cert = ssl.certificate_bundle
            next if cert.nil?
            cert = cert.gsub("\\n", "\r\n") # Force new lines between certificates.
            cmds << %Q[echo "#{cert}" > #{lb.ext_cert_dir}/#{cert_name}.pem]
          end
        end
        # Find LetsEncrypt certs
        lb.users.joins(:lets_encrypts).uniq.each do |u|
          u.lets_encrypts.each do |le|
            cert = le.certificate_bundle
            next if cert.nil?
            cmds << %Q[echo "#{cert}" > #{lb.ext_cert_dir}/le_cert#{le.id}.pem]
          end
        end
        cmds << %Q[echo "#{lb.deployable_shared_certificate}" > #{lb.ext_dir}/shared_cert.pem] unless lb.deployable_shared_certificate.nil?
        cmds << %Q[echo "#{dhparam}" > #{lb.ext_dir}/dhparam.pem]
        unless cmds.empty?
          # Group certificates into bundles of 10 to load on the servers
          cmds = cmds.to_set.each_slice(10).to_a
          cmds.each do |cmd|
            client.client.exec!(cmd.join(" && "))
          end
        end
      end
    end

    def deploy_config!
      lb.ext_ip.each do |i|
        is_node = Node.find_by("public_ip = ? OR primary_ip = ? OR hostname = ?", i, i, i)
        next if is_node && !is_node.online?
        auth = ClusterAuthService.new(lb)
        auth.node = is_node
        auth_token = auth.generate_auth_token!
        cmd = %Q(bash -c 'if [ ! -f #{lb.ext_dir}/default.http ]; then curl --insecure -H "Authorization: Bearer #{auth_token}" #{PORTAL_HTTP_SCHEME}://#{Setting.hostname}/api/stacks/load_balancers/assets/default > #{lb.ext_dir}/default.http; fi;' && curl --insecure -H "Authorization: Bearer #{auth_token}" #{PORTAL_HTTP_SCHEME}://#{Setting.hostname}/api/stacks/load_balancers > #{lb.ext_config} && #{lb.ext_reload_cmd})
        ssh_port = is_node ? is_node.ssh_port : 22
        begin
          DockerSSH::Node.new("ssh://#{i}:#{ssh_port}", { key: "#{Rails.root}/#{ENV['CS_SSH_KEY']}" }).client.exec!(cmd)
        rescue => e
          SystemEvent.create!(
            message: "Unable to provision LoadBalancer: #{lb.label}",
            log_level: 'warn',
            data: {
              'message' => e.message
            },
            event_code: 'c1f6b5853d5814d0'
          )
          next
        end
      end
    end

  end
end
