##
# # Generate Basic Auth API Credentials
#
class Api::Admin::Users::ApiCredentialsController < Api::Admin::Users::BaseController

  ##
  # Generate Credentials
  #
  # `POST /api/users/{user_id}/api_credentials`
  #
  # @example Create Credentials
  #     {
  #       "api_credential": {
  #         "name": "" # This will be visible in the user's profile.
  #       }
  #     }
  #
  # @example Response
  #     {
  #       "api_credential": {
  #         "id": 0,
  #         "username": "",
  #         "password": ""
  #       }
  #     }
  def create
    @api_credential = @user.api_credentials.new(api_params)
    @api_credential.current_user = current_user
    if @api_credential.save
      msg = {
        api_credential: {
          id: @api_credential.id,
          username: @api_credential.username,
          password: @api_credential.generated_password
        }
      }
      respond_to do |format|
        format.json { render json: msg, status: :created }
        format.xml { render xml: msg, status: :created }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @api_credential.errors.full_messages }, status: :unprocessable_entity }
        format.xml { render xml: { errors: @api_credential.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  ##
  # Delete Credentials
  #
  # `DELETE /api/users/{user_id}/api_credentials/{id}`
  #
  def destroy
    @api_credential = @user.api_credentials.find_by(id: params[:id])
    if @api_credential.nil?
      respond_to do |format|
        format.any(:json, :xml) { head :not_found }
      end
    else
      @api_credential.current_user = current_user
      if @api_credential.destroy
        respond_to do |format|
          format.any(:json, :xml) { head :ok }
        end
      else
        respond_to do |format|
          format.json { render json: { errors: @api_credential.errors.full_messages }, status: :unprocessable_entity }
          format.xml { render xml: { errors: @api_credential.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end
  end

  private

  def api_params
    params.require(:api_credential).permit(:name)
  end

end
