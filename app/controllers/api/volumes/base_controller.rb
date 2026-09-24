class Api::Volumes::BaseController < Api::ApplicationController
  api_scope read: :project_read, write: :project_write

  before_action :find_volume

  private

  def find_volume
    @volume = Volume.find_for(current_user, id: params[:volume_id])
    api_obj_missing if @volume.nil?
  end
end
