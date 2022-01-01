class UsersApiController < AuthController

  def create
    current_user.current_user = current_user
    @api_secret = current_user.generate_api_credentials!
    audit = Audit.create_from_object!(current_user, 'updated', request.remote_ip, current_user)
    audit.update_attribute :raw_data, 'Created API Credentials'
    if @api_secret.nil?
      redirect_to "/users/edit", alert: I18n.t('users.api.error')
    else
      render template: 'users/api/show'
    end
  rescue
    redirect_to "/users/edit", alert: I18n.t('users.api.error')
  end

  def destroy
    current_user.update(
      api_key: nil,
      api_secret: nil
    )
    audit = Audit.create_from_object!(current_user, 'updated', request.remote_ip, current_user)
    audit.update_attribute :raw_data, 'Deleted API Credentials'
    redirect_to "/users/edit"
  end

end
