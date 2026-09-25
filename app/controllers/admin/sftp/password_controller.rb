##
# =SFTP Password Controller
#
# GET /admin/sftp/:sftp_id/password
#   Returns the password for given SFTP container.
#
# POST /admin/sftp/:sftp_id/password
#   Replaces the password and rebuilds the SFTP container. Open SSH, SFTP, and cloud shell
#   sessions are disconnected; the new password takes effect once the rebuild completes.
#
class Admin::Sftp::PasswordController < Admin::Sftp::BaseController
  def index
    if request.xhr?
      render plain: @container.password, layout: false
    else
      redirect_to "/admin/sftp/#{@container.id}"
    end
  end

  def create
    audit = Audit.create_from_object!(@container, "updated", request.remote_ip, current_user)
    service = SftpServices::RotatePasswordService.new(@container, audit)
    if service.perform
      redirect_to "/admin/sftp/#{@container.id}", notice: "SSH password rotated. It takes effect once the SSH container rebuild completes."
    else
      redirect_to "/admin/sftp/#{@container.id}", alert: service.errors.join(" ")
    end
  end
end
