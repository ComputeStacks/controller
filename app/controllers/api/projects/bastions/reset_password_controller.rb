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
  # (`pw_auth`) is disabled.
  #
  # Responds with `202 Accepted` and the bastion, including its new password:
  #
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
  # If the rebuild cannot be started (for example, the node is offline or another action
  # is in progress on the bastion), the password is left unchanged and the response is
  # `422 Unprocessable Entity` with `errors`.
  #
  def create
    audit = Audit.create_from_object!(@bastion, "updated", request.remote_ip, current_user)
    service = SftpServices::RotatePasswordService.new(@bastion, audit)
    return api_obj_error(service.errors) unless service.perform
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/bastions/show", status: :accepted }
    end
  end

  private

  def find_bastion
    @bastion = @deployment.sftp_containers.find_by(id: params[:bastion_id])
    api_obj_missing(["Unknown bastion"]) if @bastion.nil?
  end
end
