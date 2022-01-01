##
# User Suspension
class Api::Admin::Users::SuspensionController < Api::Admin::Users::BaseController

  ##
  # Suspend a user
  #
  # `POST /api/admin/users/{id}/suspension`
  #
  def create
    @user.update active: false
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

  ##
  # Activate a user
  #
  # `delete /api/admin/users/{id}/suspension`
  #
  def destroy
    @user.update active: true
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

end
