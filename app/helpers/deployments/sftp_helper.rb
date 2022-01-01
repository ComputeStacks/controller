module Deployments::SftpHelper

  def sftp_path(sftp)
    "/deployments/#{sftp.deployment.token}/sftp/#{sftp.id}"
  end

  def sftp_password_path(sftp)
    "#{sftp_path(sftp)}/password"
  end

end