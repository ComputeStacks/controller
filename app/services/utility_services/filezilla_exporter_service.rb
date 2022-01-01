module UtilityServices
  ##
  # Export FileZilla File
  class FilezillaExporterService

    attr_accessor :user,
                  :deployment

    def intialize
      self.user = nil
      self.deployment = nil
    end

    def mimme_type
      :xml
    end

    def file_name
      "FileZilla.xml"
    end

    def perform
      return nil if user.nil? && deployment.nil?
      return generate_config(Deployment::ContainerService.find_all_for(user)) if user
      # File.open("FileZilla.xml", "w") { |f| f << result }
      generate_config(deployment.services) if deployment
    end

    private

    def generate_config(services)
      header = %Q(<?xml version="1.0" encoding="UTF-8"?><FileZilla3 version="3.56.2" platform="mac"><Servers><Folder expanded="1">#{Setting.app_name})
      footer = %Q(</Folder></Servers></FileZilla3>)
      projects = {}
      services.each do |service|
        next unless service.requires_sftp_containers?
        next if service.volumes.sftp_enabled.empty?
        sftp = service.sftp_containers.first
        next if sftp.nil?
        projects[service.deployment.name] = [] if projects[service.deployment.name].nil?
        server = []
        multiple_vols = service.volumes.sftp_enabled.count > 1
        service.volumes.sftp_enabled.each do |vol|
          server << "<Server><Host>#{sftp.ip_addr}</Host>"
          server << "<Port>#{sftp.public_port}</Port>"
          server << "<Protocol>1</Protocol>"
          server << "<Type>0</Type>"
          server << "<User>sftpuser</User>"
          server << "<Pass>#{sftp.password}</Pass>" if sftp.pw_auth
          server << "<Logontype>1</Logontype>"
          server << "<EncodingType>Auto</EncodingType>"
          server << "<BypassProxy>0</BypassProxy>"
          server << "<Name>#{multiple_vols ? "#{service.label}-#{vol.label}" : service.label}</Name>"
          server << "<RemoteDir>1 0 4 home 8 sftpuser 4 apps #{service.name.length} #{service.name} #{vol.label.length} #{vol.label}</RemoteDir>"
          server << "<SyncBrowsing>0</SyncBrowsing>"
          server << "<DirectoryComparison>0</DirectoryComparison></Server>"
        end
        projects[service.deployment.name] << server.join("")
      end
      projects.each_key do |p|
        header += %Q(<Folder expanded="0">)
        header += p
        header += projects[p].join("")
        header += "</Folder>"
      end
      header + footer
    end

  end
end
