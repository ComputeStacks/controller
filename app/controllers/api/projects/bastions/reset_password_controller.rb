##
# Bastion Password Reset
class Api::Projects::Bastions::ResetPasswordController < Api::Projects::BaseController
  before_action :find_bastion

  ##
  # Reset Bastion Password
  #
  # `POST /api/projects/{project-id}/bastions/{id}/reset_password`
  #
  # **OAuth AuthorizationRequired**: `project_write`
  #
  # Generates a new password and rebuilds the bastion (SSH) container. The rebuild
  # disconnects any open SSH, SFTP, and cloud shell sessions, and the new password takes
  # effect once the rebuild completes. The password is rotated even while password auth
  # (`pw_auth`) is disabled. The SSH port and the project's volumes are unchanged.
  #
  # * `callback`: Object | Optional. Notified when the rebuild finishes, successfully or not.
  #     * `authorization`: String
  #     * `url`: String
  #
  # Responds with `202 Accepted`, the rebuild event, and the bastion, including its new
  # password:
  #
  # * `event_id`: Integer | The rebuild event.
  # * `bastion`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `status`: String
  #     * `node_id`: Integer
  #     * `ip_addr`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `port`: Integer
  #     * `pw_auth`: Boolean | If true, password auth is enabled.
  #     * `username`: String
  #     * `password`: String | The new password.
  #
  # If the rebuild cannot be started, the password is left unchanged. When that is because
  # the bastion's node is in maintenance or offline (or it has no node), the response is
  # `409 Conflict` with `errors`, `code` (`node_maintenance` or `node_offline`) and
  # `node_status`. Otherwise (for example, another action is in progress on the bastion) it
  # is `422 Unprocessable Entity` with `errors`. The callback is normally not called in
  # either case, but if the rebuild is refused after its event was created (such as another
  # action starting at the same moment), that event is canceled and the callback reports
  # the failure.
  #
  def create
    callback = params[:callback]
    if callback.present? && !valid_callback?(callback)
      return api_obj_error(["callback must be an object with a string url and authorization."])
    end
    audit = Audit.create_from_object!(@bastion, "updated", request.remote_ip, current_user)
    service = SftpServices::RotatePasswordService.new(@bastion, audit)
    if callback.present?
      service.callback_auth = callback[:authorization]
      service.callback_url = callback[:url]
    end
    unless service.perform
      if service.error_code
        return api_node_unavailable(service.errors, code: service.error_code,
          node_status: Nodes::CustomerStatusPresenter.for_node(@bastion.node))
      end
      return api_obj_error(service.errors)
    end
    @event = service.event
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/bastions/show", status: :accepted }
    end
  end

  private

  def valid_callback?(callback)
    callback.is_a?(ActionController::Parameters) &&
      callback[:url].is_a?(String) &&
      (callback[:authorization].nil? || callback[:authorization].is_a?(String))
  end

  def find_bastion
    @bastion = @deployment.sftp_containers.find_by(id: params[:bastion_id])
    api_obj_missing(["Unknown bastion"]) if @bastion.nil?
  end
end
