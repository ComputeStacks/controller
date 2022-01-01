class Api::Volumes::BaseController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update create destroy], unless: :current_user

  before_action :find_volume

  private

  def find_volume
    @volume = Volume.find_for(current_user, id: params[:volume_id])
    return api_obj_missing if @volume.nil?
  end

end
