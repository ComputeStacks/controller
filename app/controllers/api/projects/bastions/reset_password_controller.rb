##
# Bastion Password Reset
class Api::Projects::Bastions::ResetPasswordController < Api::Projects::BaseController

  before_action :find_bastion

  ##
  # Reset SFTP Container Password
  #
  # `POST /api/projects/{project-id}/bastions/{id}/reset_password`
  #
  def create

    unless @bastion.update(password: SecureRandom.urlsafe_base64(10).gsub("_", "").gsub("-", ""))
      return api_obj_error(@bastion.errors.full_messages)
    end

    audit = Audit.create_from_object!(@bastion, 'updated', request.remote_ip, current_user)
    power_action = PowerCycleContainerService.new(@bastion, 'rebuild', audit)
    result = power_action.perform
    return api_obj_error(result.errors) unless result
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/bastions/show', status: :accepted }
    end
  end

  private

  def find_bastion
    @bastion = @deployment.sftp_containers.find_by(id: params[:bastion_id])
    return api_obj_missing if @bastion.nil?
    return api_obj_missing unless @bastion.can_edit?(current_user)
  end

end
