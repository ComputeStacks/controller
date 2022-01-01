class UsersController < ApplicationController

  before_action :authenticate_user!, except: [:authy_sms, :disconnect]
  before_action :second_factor!, except: [:authy_sms, :disconnect]

  def update
    # @user = User.find_by(id: current_user.id)
    if user_params[:current_password].blank?
      params[:user].delete :current_password
      params[:user].delete(:password)
      params[:user].delete(:password_confirmation)
    else
      current_user.tmp_updated_password = user_params[:password]
    end

    # When coming from password change fields
    if params[:user].empty?
      redirect_to "/users/security", alert: "No changes made"
      return false
    end

    if current_user.valid? && current_user.update(user_params)
      Audit.create_from_object!(current_user, 'updated', request.remote_ip, current_user)
      sign_in current_user, bypass: true
      redirect_to "/users/edit", notice: I18n.t('devise.registrations.updated')
    else
      render template: user_params[:current_password].blank? ? 'users/edit' : 'users/security/index'
    end
  end

  # @deprecated
  def authy_sms
    @resource = current_user.nil? ? User.find_by(id: session["user_id"]) : current_user
    if @resource.nil?
      render :json => {:sent => false, :message => "User couldn't be found."}
      return false
    end
    response = Authy::API.request_sms(:id => @resource.authy_id, :force => true)
    render :json => {:sent => response.ok?, :message => response.message}
  end

  # @deprecated
  def authy_disable
    if current_user.update_attribute :authy_enabled, false
      audit = Audit.create_from_object!(current_user, 'updated', request.remote_ip, current_user)
      audit.update_attribute :raw_data, 'disabled authy'
      flash[:notice] = "Authy disabled."
    else
      flash[:alert] = "There was a problem. Please contact support."
    end
    redirect_to "/profile"
  end

  def disconnect
    if current_user
      redirect_to "/"
    else
      render template: 'users/logout', layout: 'devise'
    end
  end

  private

  def user_params
    params.require(:user).permit(:fname, :lname, :email, :current_password, :password, :password_confirmation, :address1, :address2, :city, :state, :country, :vat, :zip, :company_name, :currency, :phone, :c_sftp_pass)
  end

end
