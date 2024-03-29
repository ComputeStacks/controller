module Containers
  module SshVolumes
    extend ActiveSupport::Concern

    ##
    # List volumes that _should_ belong to this SSH container
    def volumes
      expected_volumes = node.volumes.where(
        deployment_id: deployment.id,
        to_trash: false,
        enable_sftp: true
      ).where.not(
        deployment: { status: 'deleting' }
      ).joins(:deployment).distinct

      result = []
      DockerVolumeLocal::Node.new(node).list_all_volumes.each do |i|
        vol = expected_volumes.select { |ii| ii.name == i.id }[0]
        next if vol.nil? || vol.container_service.nil?
        image = vol.container_service.container_image
        next unless image.enable_sftp
        next if Volume.excluded_roles.include?(image.role.downcase) # Hard code block sftp container.
        result << {
          'service' => vol.container_service.name,
          'volume' => vol.name,
          'label' => vol.label.blank? ? vol.container_service.label : vol.label
        }
      end
      result
    end

    def volume_binds
      volumes.map { |vol| "#{vol['volume']}:/home/sftpuser/apps/#{vol['service']}/#{vol['label']}" }
    end

  end
end
