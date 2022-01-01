class Admin::Sftp::RemoteVolumesController < Admin::Sftp::BaseController

  def index
    @volumes = @container.attached_volumes
    render template: "admin/volumes/shared/remote_volumes", layout: false
  end

end