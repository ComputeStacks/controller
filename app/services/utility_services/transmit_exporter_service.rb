module UtilityServices
  ##
  # Transmit Saved Profiles
  class TransmitExporterService

    attr_accessor :user,
                  :deployment

    def intialize
      self.user = nil
      self.deployment = nil
    end

    def mimme_type
      "application/octet-stream"
    end

    def file_name
      "Transmit Servers.transmitServers"
    end

    def perform
      return nil if user.nil? && deployment.nil?
      return generate_config(Deployment::ContainerService.find_all_for(user)) if user
      generate_config(deployment.services) if deployment
    end

    private

    def generate_config(services)
      data = []
      services.each do |service|
        next unless service.requires_sftp_containers?
        next if service.volumes.sftp_enabled.empty?
        sftp = service.sftp_containers.first
        next if sftp.nil?
        multiple_vols = service.volumes.sftp_enabled.count > 1
        service.volumes.sftp_enabled.each do |vol|
          server = {
            "showFoldersAboveFiles" => false,
            "protocol" => 1397118032,
            "serverType" => 0,
            "userFolderLinking" => false,
            "passwordInKeychain" => false,
            "useDockSend" => false,
            "showHiddenFiles" => true,
            "address" => sftp.ip_addr,
            "usePassiveMode" => false,
            "localPlaces" => [],
            "fileListEncoding" => 4,
            "username" => "sftpuser",
            "remotePath" => %Q(/home/sftpuser/apps/#{service.name}/#{vol.label}),
            "remotePlaces" => [],
            "name" => %Q([#{service.deployment.name}] #{multiple_vols ? "#{service.label}-#{vol.label}" : service.label}),
            "port" => sftp.public_port
          }
          server["password"] = sftp.password if sftp.pw_auth
          data << server
        end
      end
      {
        "__NSArrayM" => {
          "NS.object.0" => {
            "name" => Setting.app_name,
            "connections" => data
          }
        }
      }.to_json
    end

  end
end
