module Containers
  module SshVolumes
    extend ActiveSupport::Concern

    ##
    # List volumes that _should_ belong to this SSH container
    def volumes
      # `awaiting_mount: false` is not optional. An awaiting-mount volume exists on the node
      # but no application container carries its bind yet, so exposing it over SFTP would let
      # the customer upload data into a volume their app cannot see AND whose backups are
      # suppressed — data that silently vanishes from view when the volume finally mounts
      # empty at the next rebuild. It becomes SFTP-visible on its own once the flag clears.
      expected_volumes = node.volumes.where(
        deployment_id: deployment.id,
        to_trash: false,
        enable_sftp: true,
        awaiting_mount: false
      ).where.not(
        deployment: {status: "deleting"}
      ).joins(:deployment).distinct

      result = []
      DockerVolumeLocal::Node.new(node).list_all_volumes.each do |i|
        vol = expected_volumes.select { |ii| ii.name == i.id }[0]
        next if vol.nil? || vol.container_service.nil?
        image = vol.container_service.container_image
        next unless image.enable_sftp
        next if Volume.excluded_roles.include?(image.role.downcase) # Hard code block sftp container.
        result << {
          "service" => vol.container_service.name,
          "volume" => vol.name,
          "label" => vol.label.blank? ? vol.container_service.label : vol.label
        }
      end
      result
    end

    def volume_binds
      volumes.map { |vol| "#{vol["volume"]}:/home/sftpuser/apps/#{vol["service"]}/#{vol["label"]}" }
    end
  end
end
