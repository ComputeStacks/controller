module Admin::NetworksHelper

  def cidr_obj(cidr)
    if cidr.container
      if cidr.container.deployment
        "#{cidr.container.name} (#{cidr.container.deployment.name})"
      else
        "#{cidr.container.name}"
      end
    elsif cidr.sftp_container
      if cidr.sftp_container.deployment
        "SFTP #{cidr.sftp_container.name}"
      else
        "SFTP #{cidr.sftp_container.name} (#{cidr.sftp_container.deployment.name})"
      end
    else
      'Not Found'
    end
  end

end
