##
# CloudShell
class Api::Projects::CloudShellController < Api::Projects::BaseController
  before_action :verify_admin

  ##
  # Generate a Cloud Shell Session
  #
  # `POST /api/projects/{project-id}/cloud_shell`
  #
  # **OAuth AuthorizationRequired**: `project_write`
  #
  # Returns:
  #
  # * `cloud_shell`: String | Link with authorization token.
  #
  def create
    unless @deployment.region.guac_available?
      return api_obj_err(["Cloud Shell Not Available"])
    end

    sftp = @deployment.sftp_containers.first
    return api_obj_err(["Missing sftp container"]) if sftp.nil?

    return api_obj_err(sftp.cloud_shell_errors) unless sftp.cloud_shell_errors.empty?

    shell_token = sftp.cloud_shell_token
    return api_obj_err(["Failed to generate auth token"]) if shell_token.blank?

    cloud_shell_url = "#{@deployment.region.guac_url}/?token=#{shell_token}"

    respond_to do |format|
      format.json { render json: {cloud_shell: cloud_shell_url} }
      format.xml { render xml: {cloud_shell: cloud_shell_url} }
    end
  end

  private

  # Only allow resource owner and admin to manage collaborators
  def verify_admin
    unless @deployment.can_administer? current_user
      head :unauthorized
    end
  end
end
