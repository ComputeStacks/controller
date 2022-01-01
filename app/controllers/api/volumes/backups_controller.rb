##
# Volume Backups
class Api::Volumes::BackupsController < Api::Volumes::BaseController

  before_action :can_perform?, only: %i[create destroy]

  ##
  # List all backups
  #
  # `GET /api/volumes/{volume-id}/backups`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `name`: String
  # * `usage`: Integer | Size on disk (deduplicated)
  # * `size`: Integer | Expanded total size
  # * `archives`: Array<String>
  #
  def index
    respond_to do |format|
      format.json { render json: @volume.repo_info }
      format.xml { render xml: @volume.repo_info }
    end
  end

  ##
  # Create a backup
  #
  # `POST /volumes/{volume-id}/backups`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `name`: String | Name of backup. Must be at least 3 characters long, and should not include spaces.
  #
  def create
    audit = Audit.create_from_object!(@volume, 'backup.create', request.remote_ip, current_user)
    @volume.current_audit = audit
    errors = []
    if params[:name].length < 3
      errors << "Name too short, must be at least 3 characters."
    else
      unless @volume.create_backup!(params[:name])
        errors << "Failed to create backup. Check volume event logs."
      end
    end
    return api_obj_error(errors) unless errors.empty?
    respond_to do |format|
      format.json { render json: {}, status: :created }
      format.xml { render xml: {}, status: :created }
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
