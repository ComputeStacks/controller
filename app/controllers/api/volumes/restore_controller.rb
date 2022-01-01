##
# Restore Volume Backup
class Api::Volumes::RestoreController < Api::Volumes::BaseController

  before_action :can_perform?, only: %i[create destroy]

  ##
  # Restore a backup
  #
  # `POST /volumes/{volume-id}/restore`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `name`: String | Name of backup to restore
  #
  def create
    audit = Audit.create_from_object!(@volume, 'backup.restore', request.remote_ip, current_user)
    @volume.current_audit = audit
    errors = []
    unless @volume.restore_backup!(params[:name])
      errors << "Failed to restore backup. Check volume event logs."
    end
    return api_obj_error(errors) unless errors.empty?
    respond_to do |format|
      format.json { render json: {}, status: :accepted }
      format.xml { render xml: {}, status: :accepted }
    end
  end

  private

  def can_perform?
    if @volume.operation_in_progress?
      respond_to do |format|
        format.json { render json: { errors: [ "Unable to perform while another operation is in progress." ] }, status: :method_not_allowed }
        format.xml { render xml: { errors: [ "Unable to perform while another operation is in progress." ] }, status: :method_not_allowed }
      end
      return false
    end
  end

end
