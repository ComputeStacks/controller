##
# =SFTP Password Controller
# Returns the password for given SFTP container.
#
# GET /admin/sftp/:sftp_id/password
#
class Admin::Sftp::PasswordController < Admin::Sftp::BaseController

  def index
    if request.xhr?
      render plain: @container.password, layout: false
    else
      redirect_to "/admin/sftp/#{@container.id}"
    end
  end

end
