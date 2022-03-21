module ContainerImages
  module ImageParamManager
    extend ActiveSupport::Concern

    class_methods do
      def system_vars
        %w(
          region.endpoint.api
          build.self.name
          build.self.name_short
          build.self.service_name
          build.self.service_name_short
          build.self.project_id
          build.self.ip
          build.self.default_domain
          build.self.default_domain_with_proto
          build.self.ec_pub_key
        )
      end
    end


    # TODO: Estimate payload size for consul. Can't exceed 512_000
    # def estimated_payload_size(); end

    def available_vars
      # Removed the following variables from the local container since the container won't know them until after it's provisioned:
      # - build.host.ip
      # - build.host.ip_with_port
      #

      # removed (10/15/19)
      # * build.self.port
      # * build.self.ip_with_port

      vars = ContainerImage.system_vars

      setting_params.each do |i|
        vars << "build.settings.#{i.name}"
      end
      dependencies.each do |i|
        i.setting_params.each do |ii|
          vars << "dep.#{i.role}.parameters.settings.#{ii.name}"
        end
        vars << "dep.#{i.role}.self.ip"
        # vars << "dep.#{i.role}.self.ip_with_port"
        # vars << "dep.#{i.role}.self.port"
      end
      vars
    end

  end
end
