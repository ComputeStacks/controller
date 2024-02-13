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
  # * `usage`: Integer | Size on disk (deduplicated)
  # * `size`: Integer | Expanded total size
  # * `archives`: Array
  #   * `id`: String | base64 encoded name
  #   * `label`: String
  #   * `created`: DateTime
  #
  def index
    data = {
      usage: @volume.backup_usage,
      size: @volume.backup_total_usage,
      archives: @volume.list_archives
    }
    respond_to do |format|
      format.json { render json: data }
      format.xml { render xml: data }
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
  # * `callback`: Object | optional webhook to call after event is finished
  #     * `authorization`: String | Right side of authorization header. Example: `Bearer 12345` or `Token 12345`
  #     * `url`: String | fully qualified URL
  #
  def create
    audit = Audit.create_from_object!(@volume, 'backup.create', request.remote_ip, current_user)
    @volume.current_audit = audit

    if params[:name].length < 3
      return api_obj_error(["Name too short, must be at least 3 characters."])
    end

    event = @volume.event_logs.new(
      locale: 'volume.backup',
      locale_keys: {},
      status: 'pending',
      audit: audit,
      event_code: 'agent-ad28e9aa1933495f'
    )

    if params[:callback]
      event.labels['callback_auth'] = params[:callback][:authorization]
      event.labels['callback_url'] = params[:callback][:url]
    end

    unless event.save
      return api_obj_error(event.errors.full_messages)
    end

    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service

    unless @volume.create_backup!(params[:name])
      event.fail! "Fatal Error"
      return api_obj_error(["Failed to create backup. Check volume event logs."])
    end

    respond_to do |format|
      format.json { render json: {}, status: :created }
      format.xml { render xml: {}, status: :created }
    end
  end

  ##
  # Delete Backup
  #
  # `DELETE /volumes/{volume-id}/backups/:name`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `name`: String | base64 encoded name of backup to delete
  # * `callback`: Object | optional webhook to call after event is finished
  #     * `authorization`: String | Right side of authorization header. Example: `Bearer 12345` or `Token 12345`
  #     * `url`: String | fully qualified URL
  #
  def destroy
    name = Base64.decode64 params[:id]
    return api_obj_error(["Missing backup name"]) if name.blank?

    audit = Audit.create_from_object!(@volume, 'backup.delete', request.remote_ip, current_user)
    @volume.current_audit = audit

    event = @volume.event_logs.new(
      locale: 'backup.delete',
      locale_keys: {},
      status: 'pending',
      audit: audit,
      event_code: 'agent-1105683bb0f948c0'
    )

    if params[:callback]
      event.labels['callback_auth'] = params[:callback][:authorization]
      event.labels['callback_url'] = params[:callback][:url]
    end

    unless event.save
      return api_obj_error(event.errors.full_messages)
    end

    event.deployments << @volume.deployment if @volume.deployment
    event.container_services << @volume.container_service

    unless @volume.delete_backup!(name)
      event.fail! "Fatal Error"
      return api_obj_error(["Failed to delete backup. Check volume event logs."])
    end

    respond_to do |format|
      format.json { render json: {}, status: :ok }
      format.xml { render xml: {}, status: :ok }
    end
  end

  private

  def can_perform?
    if @volume.operation_in_progress?
      respond_to do |format|
        format.json { render json: { errors: [ "Unable to perform while another operation is in progress." ] }, status: :method_not_allowed }
        format.xml { render xml: { errors: [ "Unable to perform while another operation is in progress." ] }, status: :method_not_allowed }
      end
    end
  end

end
