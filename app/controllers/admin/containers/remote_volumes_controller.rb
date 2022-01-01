class Admin::Containers::RemoteVolumesController < Admin::Containers::BaseController

  def index
    @volumes = @container.attached_volumes
    render template: "admin/volumes/shared/remote_volumes", layout: false
  end

end