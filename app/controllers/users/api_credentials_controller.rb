class Users::ApiCredentialsController < AuthController

  before_action :load_api_credential, except: %i[index new create]

  def index
    @api_credentials = current_user.api_credentials.order(created_at: :desc)
  end

  def new
    @api_credential = current_user.api_credentials.new
  end

  def edit; end

  def update
    if @api_credential.update(api_params)
      redirect_to "/users/api_credentials", success: 'Updated successfully'
    else
      render template: 'users/api_credentials/edit'
    end
  end

  def create
    @api_credential = current_user.api_credentials.new(api_params)
    @api_credential.current_user = current_user
    render template: @api_credential.save ? 'users/api_credentials/show' : 'users/api_credentials/new'
  end

  def destroy
    if @api_credential.destroy
      flash[:success] = 'Success'
    else
      flash[:alert] = @api_credential.errors.full_messages.join('. ')
    end
    redirect_to '/users/api_credentials'
  end

  private

  def api_params
    params.require(:user_api_credential).permit(:name)
  end

  def load_api_credential
    @api_credential = current_user.api_credentials.find_by(id: params[:id])
    if @api_credential.nil?
      return redirect_to('/users/api_credentials', alert: 'Unknown credential.')
    end
    @api_credential.current_user = current_user
  end

end
