class Auth::OauthApplicationsController < Doorkeeper::ApplicationsController

  include BelcoWidget
  include EnforceSecondFactor
  include LogPayload
  include SentrySetup

  respond_to :html # Don't respond to json requests here.

  before_action :authenticate_user!
  before_action :second_factor!

  before_action :load_owner, only: %i[show]

  def index
    if current_user.is_admin
      # While admins can modify ALL applications, restrict the listing to just public and their applications
      @applications = Doorkeeper::Application.where("owner_id is null OR owner_id = ?", current_user.id).ordered_by(:created_at)
    else
      @applications = current_user.oauth_applications.ordered_by(:created_at)
    end
  end

  def new
    @application = Doorkeeper::Application.new
    @application.scopes = ["public"]
  end

  def create
    @application = Doorkeeper::Application.new(application_params)
    @application.owner = current_user unless current_user.is_admin

    if @application.save
      flash[:notice] = I18n.t(:notice, scope: %i[doorkeeper flash applications create])

      respond_to do |format|
        format.html { redirect_to oauth_application_url(@application) }
        format.json { render json: @application }
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.json do
          errors = @application.errors.full_messages

          render json: { errors: errors }, status: :unprocessable_entity
        end
      end
    end
  end

  private

  def set_application
    if current_user.is_admin
      @application = Doorkeeper::Application.find_by(id: params[:id])
    else
      @application = current_user.oauth_applications.find_by(id: params[:id])
    end
    if @application.nil?
      return redirect_to action: :index, alert: "Unknown application"
    end
  end

  def load_owner
    @owner = if @application.owner_id.blank?
               nil
             else
               User.find_by(id: @application.owner_id)
             end
  end

  def application_params
    if current_user.is_admin
      params.require(:doorkeeper_application).permit(
        :name, :redirect_uri, :confidential, :owner_id, scopes: []
      )
    else
      params.require(:doorkeeper_application).permit(
        :name, :redirect_uri, :confidential, scopes: []
      )
    end
  end

end
