class Admin::Sftp::BaseController < Admin::ApplicationController

  before_action :find_container

  private

  def find_container
    @container = Deployment::Sftp.find_by(id: params[:sftp_id])
    return redirect_to("/admin/deployments", alert: "Unknown container") if @container.nil?
  end

end