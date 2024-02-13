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
  # * `name`: String | Name of backup to restore (base64 decode of id)
  # * `callback`: Object | optional webhook to call after event is finished
  #     * `authorization`: String | Right side of authorization header. Example: `Bearer 12345` or `Token 12345`
  #     * `url`: String | fully qualified URL
  #
  def create
    audit = Audit.create_from_object!(@volume, 'backup.restore', request.remote_ip, current_user)
    @volume.current_audit = audit

    event = @volume.event_logs.new(
      locale: 'volume.restore',
      locale_keys: {},
      status: 'pending',
      audit: audit,
      event_code: 'agent-bde07117ae85937d'
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


    unless @volume.restore_backup!(params[:name])
      event.fail! "Fatal Error"
      return api_obj_error(["Failed to restore backup. Check volume event logs."])
    end

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
