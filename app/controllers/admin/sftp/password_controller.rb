##
# =SFTP Password Controller
# Returns the password for given SFTP container.
#
# GET /admin/sftp/:sftp_id/password
#
class Admin::Sftp::PasswordController < Admin::Sftp::BaseController

  def index
    render plain: @container.password, layout: false
  end

end