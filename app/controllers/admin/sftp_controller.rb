class Admin::SftpController < Admin::ApplicationController

  before_action :find_container, only: %w(show)

  def index
    @containers = Deployment::Sftp.sorted.paginate per_page: 30, page: params[:page]
  end

  def show
    @volumes = @container.volumes
  end

  private

  def find_container
    @container = Deployment::Sftp.find_by(id: params[:id])
    return redirect_to("/admin/deployments", alert: "Unknown container") if @container.nil?
  end

end