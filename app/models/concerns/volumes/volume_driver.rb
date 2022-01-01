module Volumes
  module VolumeDriver
    extend ActiveSupport::Concern

    def uses_clustered_storage?
      volume_driver_client.clustered_storage?
    end

    def provisioned?
      volume_client.provisioned?
    rescue
      false
    end

    def destroy_volume!
      volume_client.destroy
    end

    def volume_client
      case volume_backend
      when 'nfs'
        DockerVolumeNfs.configure ssh_key: ENV['CS_SSH_KEY']
        DockerVolumeNfs::Volume.new self
      else
        DockerVolumeLocal::Volume.new self
      end
    end

    def volume_driver_client
      case volume_backend
      when 'nfs'
        DockerVolumeNfs.configure ssh_key: ENV['CS_SSH_KEY']
        DockerVolumeNfs
      else
        DockerVolumeLocal
      end
    end

  end
end
