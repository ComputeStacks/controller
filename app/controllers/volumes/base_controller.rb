class Volumes::BaseController < AuthController

  before_action :find_volume

  private

  def find_volume
    @volume = Volume.find_for current_user, { id: params[:volume_id] }
    if @volume.nil?
      if request.xhr?
        render plain: "Volume does not exist.", layout: false
      else
        redirect_to "/volumes", alert: 'Unknown volume.'
      end
      return false
    end
  end

end
