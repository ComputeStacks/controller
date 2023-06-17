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

  # @param [Network] network
  def net_in_use_label(network)
    if network.has_clustered_networking?
      "#{network.addresses.count} Addresses"
    else
      "#{network.child_networks.active.count} Subnets"
    end
  end

end
