# DEVISE Registration Controller
class RegistrationsController < Devise::RegistrationsController

  before_action :authenticate_user!
  before_action :second_factor!

  def edit
    @user = current_user
    render layout: 'application', template: 'users/edit'
  end

end
