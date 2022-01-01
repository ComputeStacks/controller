class Admin::UsersController < Admin::ApplicationController

  before_action :load_user, except: [:index, :create, :new]

  def index
    users = User
    users = case params[:state]
            when 'active'
              users.where(active: true)
            when 'inactive'
              users.where(active: false)
            else
              users
            end
    users = case params[:role]
            when 'admin'
              users.where(is_admin: true)
            when 'user'
              users.where(is_admin: false)
            else
              users
            end
    users = case params[:group].to_i
            when 0
              users
            else
              ug = UserGroup.find_by(id: params[:group])
              ug ? users.where(user_group: ug) : users
            end
    users = case params[:product].to_i
            when 0
              users
            when -1
              users.with_active_subscriptions
            when -2
              users.where("id not in (?)", users.select(:id).where(subscriptions: { active: true }).joins(:subscriptions).distinct.pluck(:id))
            else
              p = Product.find_by(id: params[:product])
              if p
                users.select("lower(users.lname), lower(users.fname), users.*").where(products: { id: p.id }, subscriptions: {active: true}).joins(:products, :subscriptions).distinct
              else
                users
              end
            end
    @users = users.sorted.paginate page: params[:page], per_page: 30
  end

  def impersonate
    # https://github.com/plataformatec/devise/wiki/How-To:-Sign-in-as-another-user-if-you-are-an-admin
    # bypass prevents 'last_sign_in_at' and 'current_sign_in' from being updated.
    # TODO: possibly replace with: https://github.com/flyerhzm/switch_user ?
    if @user.is_support_admin?
      redirect_to "/admin/users/#{@user.id}", alert: "Unable to impersonate support user."
    else
      audit = Audit.create_from_object!(@user, 'impersonated', request.remote_ip, current_user)
      @user.current_audit = audit
      @user.disable_2fa!
      sign_in(:user, @user, bypass: true)
      @user.enable_2fa!
      redirect_to @user.is_admin ? '/admin' : '/'
    end
  end

  def show
    @deployments = @user.deployments
    @images = @user.container_images
    @zones = @user.dns_zones
    @volumes = @user.volumes
    @certs = @user.lets_encrypts
    if params[:js]
      case params[:req]
      when 'billing_events'
        render template: 'admin/users/show/app_events', layout: false
      when 'services'
        render template: 'admin/users/show/resource_stats', layout: false
      end
      return false
    end
  end

  def edit; end

  def update
    if user_params[:password].blank?
      params[:user].delete(:password)
      params[:user].delete(:password_confirmation)
    else
      @user.tmp_updated_password = user_params[:password]
    end
    if @user.valid? && @user.update(user_params)
      redirect_to @base_url, notice: "Successfully updated user #{@user.email}"
    elsif @user.errors
      flash[:alert] = "#{@user.errors.full_messages.join(' ')}"
      render template: 'admin/users/edit'
    else
      redirect_to @base_url, alert: 'Unknown error.'
    end
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.skip_confirmation!
    @user.tmp_updated_password = user_params[:password]
    if @user.valid? && @user.save
      redirect_to "/admin/users/#{@user.id}-#{@user.full_name.parameterize}", notice: "User #{@user.email} successfully created!"
    else
      flash[:alert] = "#{@user.errors.full_messages.join(' ')}"
      render template: 'admin/users/new'
    end
  end

  def destroy
    if @user.is_admin
      redirect_to @base_url, alert: 'Unable to delete an Administrator. Please first remove their admin role.'
    else
      if @user.destroy
        redirect_to '/admin/users', notice: "Successfully deleted user."
      else
        redirect_to '/admin/users', alert: "Error! #{@user.errors.full_messages.join(' ')}"
      end
    end
  end

  def suspend
    @user.update_attribute :active, false
    redirect_to @base_url, notice: 'User suspended.'
  end

  def unsuspend
    @user.update_attribute :active, true
    redirect_to @base_url, notice: 'User activated.'
  end

  private

  def user_params
    params.require(:user).permit(:fname, :lname, :timezone, :lang, :active, :email, :locale, :is_admin, :currency, :password, :password_confirmation, :external_id, :bypass_billing, :address1, :address2, :city, :state, :country, :zip, :vat, :phase_started, :comments, :company_name, :user_group_id, :phone)
  end

  def load_user
    @user = User.find_by(id: params[:id])
    if @user.nil?
      redirect_to "/admin/users", alert: 'Unknown User.'
      return false
    end
    @user.current_user = current_user
    @base_url = "/admin/users/#{@user.id}-#{@user.full_name.parameterize}"
  end

end
