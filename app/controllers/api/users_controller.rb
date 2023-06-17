##
# Your User API
class Api::UsersController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :profile_read }, only: %i[show], unless: :current_user
  before_action -> { doorkeeper_authorize! :profile_update }, only: %i[update], unless: :current_user
  before_action -> { doorkeeper_authorize! :register }, only: :create, unless: :current_user

  ##
  # View your user account
  #
  # `GET /api/users`
  #
  # **OAuth AuthorizationRequired**: `profile_read`
  #
  # `unprocessed_usage` is the amount the user has accrued, but not yet transferred to the billing system for billing.
  #
  # * `user`: Object
  #     * `id`: Integer
  #     * `fname`: String
  #     * `lname`: String
  #     * `email`: String
  #     * `phone`: String
  #     * `address1`: String
  #     * `address2`: String
  #     * `city`: String
  #     * `company_name`: String
  #     * `country`: String
  #     * `timezone`: String
  #     * `currency`: Object
  #         * `code`: String
  #         * `symbol`: String
  #     * `c_sftp_pass`: Boolean - Enable SFTP Auth on all new projects.
  #     * `zip`: String
  #     * `vat`: String
  #     * `state`: String
  #     * `locale`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `billing_plan`: Object
  #         * `id`: Integer
  #         * `name`: String
  #     * `services`: Object
  #         * `projects`: Integer
  #         * `containers`: Integer
  #         * `container_services`: Integer
  #         * `container_images`: Integer
  #         * `container_registries`: Integer
  #         * `dns_zones`: Integer
  #     * `quota`: Object
  #         * `{{kind}}`: Object
  #             * `current`: Integer
  #             * `quota`: Integer
  #             * `is_over`: Boolean
  #             * `available`: Integer
  #     * `unprocessed_usage`: Decimal
  #
  # @example
  #    {
  #      "user": {
  #        "id": 1,
  #        "fname": "John",
  #        "lname": "Doe",
  #        "email": "john@example.com",
  #        "phone": null,
  #        "address1": null,
  #        "address2": null,
  #        "city": null,
  #        "company_name": null,
  #        "country": "US",
  #        "timezone": "America/Los_Angeles",
  #        "currency": {
  #          "code": "USD",
  #          "symbol": "$"
  #        },
  #        "zip": null,
  #        "vat": null,
  #        "state": null,
  #        "locale": "en",
  #        "created_at": "2019-04-04T07:36:50.637Z",
  #        "updated_at": "2019-09-19T19:16:07.155Z",
  #        "billing_plan": {
  #          "id": 1,
  #          "name": "default"
  #        },
  #        "services": {
  #          "projects": 0,
  #          "containers": 0,
  #          "container_services": 0,
  #          "container_images": 1,
  #          "container_registries": 0,
  #          "dns_zones": 0
  #        },
  #        "quota": {
  #          "containers": {
  #            "current": 0,
  #            "quota": 250,
  #            "is_over": false,
  #            "available": 250
  #          },
  #          "cr": {
  #            "current": 0,
  #            "quota": 20,
  #            "is_over": false,
  #            "available": 20
  #          },
  #          "dns_zones": {
  #            "current": 0,
  #            "quota": 250,
  #            "is_over": false,
  #            "available": 250
  #          }
  #        },
  #        "unprocessed_usage": 0.0
  #      }
  #    }

  def show;
  end

  ##
  # Update your user account
  #
  # `PATCH /api/users`
  #
  # **OAuth AuthorizationRequired**: `profile_update`
  #
  # * `user`: Object
  #     * `fname`: String
  #     * `lname`: String
  #     * `email`: String
  #     * `locale`: String | locale code (example: `en`)
  #     * `city`: String
  #     * `state`: String
  #     * `zip`: String
  #     * `c_sftp_pass`: Boolean
  #     * `country`: String | Should be in the 2 digit format, e.g. US, CA, NL, etc.
  #     * `address1`: String
  #     * `address2`: String
  #     * `company_name`: String
  #     * `phone`: String
  #     * `currency`: String
  #     * `merge_labels`: Object

  def update
    user   = current_user
    status = :ok
    msg    = {}
    unless user.update(user_params)
      msg    = { errors: user.errors.full_messages }
      status = :bad_request
    end
    respond_to do |format|
      format.json { render json: msg, status: status }
      format.xml { render xml: msg, status: status }
    end
  end

  ##
  # Create New User
  #
  # `POST /api/users`
  #
  # **OAuth AuthorizationRequired**: `register`
  #
  # This is a special endpoint for use in conjunction with our embeddable interface.
  # Users are not expected to be able to login directly after signup.
  #
  # * Only available using the `register` scope.
  # * This will automatically generate api credentials
  # * This will not send an email confirmation
  # * If no email is provided, or if the email is already in use, this will generate a unique email address
  #
  # * `user`: Object
  #     * `fname`: String (required)
  #     * `lname`: String (required)
  #     * `email`: String
  #     * `locale`: String | locale code (example: `en`)
  #     * `city`: String
  #     * `state`: String
  #     * `zip`: String
  #     * `c_sftp_pass`: Boolean
  #     * `country`: String | Should be in the 2 digit format, e.g. US, CA, NL, etc.
  #     * `address1`: String
  #     * `address2`: String
  #     * `company_name`: String
  #     * `phone`: String
  #     * `currency`: String
  #     * `merge_labels`: Object
  #     * `provider`: String | The name of the provider we're generating credentials for, such as `cpanel`. Default is cpanel.
  #     * `provider_server`: String (required) | The url or unique server name of the provider's server. This is used to scope the username.
  #     * `provider_username`: String (required) | the user's username on the server.
  #
  # @example
  #   {
  #     "user": {
  #       "id": "integer",
  #       "fname":  "string",
  #       "lname":  "string",
  #       "email":  "string",
  #       "locale": "string",
  #       "company_name": "string",
  #       "external_id": "string",
  #       "api":    {
  #         "username": "string",
  #         "password": "string"
  #       },
  #       "labels": {
  #         "key":       "value",
  #         "other_key": {
  #           "key": "value"
  #         }
  #       }
  #     }
  #   }
  #
  def create
    @user = User.new(user_params)
    if user_params[:currency].blank?
      @user.currency = ENV['CURRENCY']
    else
      @user.currency = user_params[:currency].upcase
    end
    @user.active = true
    if params[:provider_username].blank? || params[:provider_server].blank?
      return api_obj_error(["missing provider settings"])
    else
      provider = params[:provider].blank? ? :cpanel : params[:provider].downcase.to_sym
      labels = { provider => { params[:provider_server] => params[:provider_username] } }
      if params[:labels]
        labels = labels.merge! create_user_params[:labels]
      end
      @user.labels = labels
    end

    # Default to en
    if @user.locale.blank? || !I18n.available_locales.include?(@user.locale.to_sym)
      @user.locale = 'en'
    end
    pw = SecureRandom.urlsafe_base64(12)
    @user.skip_confirmation!
    @user.password = pw
    @user.password_confirmation = pw
    @user.tmp_updated_password  = pw
    # Generate an email if the email already exists, or if none is supplied.
    if @user.email.blank? || User.where(email: @user.email).exists?
      @user.email = "#{params[:provider_username]}_#{SecureRandom.hex(6)}@#{Setting.hostname.split(":").first}"
    end
    if @user.save
      @api_credential = @user.api_credentials.create!(name: "generated-on-signup")
      respond_to do |format|
        format.any(:json, :xml) { render template: 'api/users/create', status: :created }
      end
    else
      api_obj_error @user.errors.full_messages
    end
  end

  private

  def create_user_params
    params.permit(
      :fname, :lname, :email, :company_name, :provider, :provider_server, :provider_username,
      :external_id, :c_sftp_pass, labels: {}
    )
  end

  def user_params # :doc:
    params.require(:user).permit(
      :fname, :lname, :email, :locale, :city, :state, :zip, :c_sftp_pass,
      :country, :address1, :address2, :company_name, :phone, :currency,
      :external_id, merge_labels: {}
    )
  end

end
