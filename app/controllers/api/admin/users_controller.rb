##
# Users
class Api::Admin::UsersController < Api::Admin::ApplicationController
  include ApiAdminFindUser

  before_action :locate_user, except: [:index, :create]

  ##
  # List all users
  #
  # `GET /api/admin/users`
  #
  # Optionally passing `?include=usage` will include their unprocessed usage.
  #
  # @example Returns
  #     {
  #       'users': [
  #         {
  #           "id": 100,
  #           "fname": "John",
  #           "lname": "Doe",
  #           "email": "j@doe.local",
  #           "active": true,
  #           "is_admin": false,
  #           "external_id": "",
  #           "currency": "USD",
  #           "confirmed_at": "2020-10-15T05:49:07.263Z",
  #           "confirmation_sent_at": null,
  #           "last_request_at": "2021-03-01T23:11:08.172Z",
  #           "last_sign_in_at": "2021-03-01T22:17:10.344Z",
  #           "current_sign_in_at": "2021-03-01T23:27:37.728Z",
  #           "sign_in_count": 0,
  #           "reset_password_sent_at": null,
  #           "locked_at": null,
  #           "failed_attempts": 0,
  #           "address1": "",
  #           "address2": "",
  #           "city": "",
  #           "state": "",
  #           "zip": "",
  #           "country": "US",
  #           "created_at": "2020-10-15T05:49:07.272Z",
  #           "updated_at": "2021-03-01T23:27:37.729Z",
  #           "security_keys": [],
  #           "billing_plan": {
  #             "id": 1,
  #             "name": "default"
  #           },
  #           "user_group": {
  #             "id": 1,
  #             "name": "default"
  #           },
  #           "external_integrations": [],
  #           "currency_symbol": "$",
  #           "current_sign_in_ip": "127.0.0.1",
  #           "last_sign_in_ip": "127.0.0.1"
  #         }
  #       ]
  #     }
  def index
    @include_usage = params[:include] == 'balance'
    @users = paginate User.sorted
    respond_to :json, :xml
  end

  ##
  # Show a single user
  #
  # `GET /api/admin/users/{id}`
  #
  # Optionally passing `?include=usage` will include their unprocessed usage.
  #
  # @example Returns
  #     {
  #       "id": 100,
  #       "fname": "John",
  #       "lname": "Doe",
  #       "email": "j@doe.local",
  #       "active": true,
  #       "is_admin": false,
  #       "external_id": "",
  #       "currency": "USD",
  #       "confirmed_at": "2020-10-15T05:49:07.263Z",
  #       "confirmation_sent_at": null,
  #       "last_request_at": "2021-03-01T23:11:08.172Z",
  #       "last_sign_in_at": "2021-03-01T22:17:10.344Z",
  #       "current_sign_in_at": "2021-03-01T23:27:37.728Z",
  #       "sign_in_count": 0,
  #       "reset_password_sent_at": null,
  #       "locked_at": null,
  #       "failed_attempts": 0,
  #       "address1": "",
  #       "address2": "",
  #       "city": "",
  #       "state": "",
  #       "zip": "",
  #       "country": "US",
  #       "created_at": "2020-10-15T05:49:07.272Z",
  #       "updated_at": "2021-03-01T23:27:37.729Z",
  #       "security_keys": [],
  #       "billing_plan": {
  #         "id": 1,
  #         "name": "default"
  #       },
  #       "user_group": {
  #         "id": 1,
  #         "name": "default"
  #       },
  #       "external_integrations": [],
  #       "currency_symbol": "$",
  #       "current_sign_in_ip": "127.0.0.1",
  #       "last_sign_in_ip": "127.0.0.1"
  #     }
  def show
    @include_usage = params[:include] == 'balance'
    respond_to :json, :xml
  end

  ##
  # Update a user
  #
  # `PATCH /api/admin/users/{id}`
  #
  # @example Update User
  #     {
  #       "user": {
  #         "email": "john@example.com"
  #       }
  #     }
  #
  def update
    if params.dig(:user, :password)
      if params[:user][:password].blank?
        params[:user].delete(:password)
        params[:user].delete(:password_confirmation)
      else
        @user.tmp_updated_password = params[:user][:password]
        if params[:user][:password_confirmation].nil?
          params[:user][:password_confirmation] = params[:user][:password]
        end
      end
    end
    if @user.is_support_admin? # Nope, no editing!
      params[:user].delete(:password)
      params[:user].delete(:password_confirmation)
      params[:user].delete(:is_admin)
      params[:user].delete(:email)
      params[:user].delete(:active)
    end
    unless @user.update(user_params)
      return api_obj_error(@user.errors.full_messages)
    end
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create a user
  #
  # `POST /admin/api/users`
  #
  # Supplying a password is optional. If none is supplied, one will be generated.
  #
  # Additional Fields
  #
  # Field            | Type    | Notes
  # -----------------|---------|---------------------------------------------------------------------------
  # `active`         | Boolean | Suspended, or un-suspended
  # `is_admin`       | Boolean | Grant admin access to this user
  # `currency`       | String  | Must be a 3-digit code, like `EUR` or `USD`.
  # `bypass_billing` | Boolean | Whether or not billing data should be processed by any billing integration
  # `company_name`   | string  |
  # `locale`         | string  | Their language in 2-digit format, examples: `en`, `fr`, `de`.
  #
  # @example Create User
  #     {
  #       "user": {
  #         "skip_email_confirm": true, # Optional, otherwise they will get an email asking them to confirm their account.
  #         "external_id": "", # A field you may use for your own purposes to store a unique id
  #         "fname": "", # required
  #         "lname": "", # required
  #         "email": "", # required. Must be unique in our system! If you skip email confirmation, it does not need to be a real email account.
  #         "password": "", # required
  #         "password_confirmation": "", # required
  #         "address1": "",
  #         "address2": "",
  #         "city": "",
  #         "state": "",
  #         "zip": "", # postal code
  #         "country": "",
  #         "phone": "",
  #         "user_group_id": "", # blank will use the default user group.
  #         "merge_labels": [
  #           {
  #             "key": "value"
  #           }
  #         ]
  #       }
  #     }
  def create
    return api_obj_error 'Missing User Object' if params[:user].nil?
    if params.dig(:user, :password).blank?
      generated_pw = SecureRandom.base64(12).gsub("=","")
      params[:user][:password] = generated_pw
      params[:user][:password_confirmation] = generated_pw
    elsif params.dig(:user, :password_confirmation).nil?
      params[:user][:password_confirmation] = params[:user][:password]
    end
    @user = User.new(user_params)
    # Default to en
    if @user.locale.blank? || !I18n.available_locales.include?(@user.locale.to_sym)
      @user.locale = 'en'
    end
    @user.skip_confirmation! if params[:user][:skip_email_confirm]
    @user.gen_sso_creds = true
    @user.tmp_updated_password = user_params[:user][:password] if user_params.dig(:user, :password)
    return api_obj_error(@user.errors.full_messages) unless @user.save
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/admin/users/create', status: :created }
    end
  rescue => e
    ExceptionAlertService.new(e, '09a2f7b02aa6f00d', current_user).perform
    api_fatal_error(e, '09a2f7b02aa6f00d')
  end

  ##
  # Delete User
  #
  # `DELETE /api/admin/users/{id}`
  #
  def destroy
    return api_obj_error(['Unable to delete support user']) if @user.is_support_admin?
    return api_obj_error(@user.errors.full_messages) unless @user.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  ##
  # Permitted User Params
  #
  def user_params # :doc:
    params.require(:user).permit(
        :fname, :lname, :active, :email, :is_admin, :currency,
        :password, :password_confirmation, :external_id, :country,
        :city, :state, :address1, :address2, :zip, :bypass_billing,
        :vat, :skip_email_confirm, :company_name, :phone, :locale,
        :user_group_id, merge_labels: {}
    )
  end

end
