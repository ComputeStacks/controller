class Admin::Volumes::BaseController < Admin::ApplicationController

  before_action :find_volume

  private

  def find_volume
    @volume = Volume.find_by(id: params[:volume_id])
    if @volume.nil?
      if request.xhr?
        render plain: "Volume does not exist.", layout: false
      else
        redirect_to "/admin/volumes", alert: 'Unknown volume.'
      end
      return false
    end
  end

end