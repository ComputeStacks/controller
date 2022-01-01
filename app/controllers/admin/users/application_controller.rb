class Admin::Users::ApplicationController < Admin::ApplicationController

  before_action :load_user

  private

  def load_user
    @user = User.find_by(id: params[:user_id])
    if @user.nil?
      if request.xhr?
        respond_to do |format|
          format.json { render json: [], status: :not_found }
          format.xml { render xml: [], status: :not_found }
        end
      else
        redirect_to "/admin/dashboard", alert: 'Unknown User.'
      end
      return false
    end
    @basepath = "/admin/users/#{@user.id}-#{@user.full_name.parameterize}"
  end
end
