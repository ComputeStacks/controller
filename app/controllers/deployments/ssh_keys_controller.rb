class Deployments::SshKeysController < Deployments::BaseController

  def index
    @ssh_keys = @deployment.project_ssh_keys
    @user_ssh_keys = UserSshKey.find_for_project @deployment
  end

  def new
    @ssh_key = @deployment.project_ssh_keys.new
  end

  def create
    @ssh_key = @deployment.project_ssh_keys.new ssh_key_params
    @ssh_key.current_audit = Audit.create_from_object! @deployment, 'updated', request.remote_ip, current_user
    if @ssh_key.save
      redirect_to "/deployments/#{@deployment.token}/ssh_keys"
    else
      render action: :new
    end
  end

  def destroy
    @ssh_key = @deployment.project_ssh_keys.find_by id: params[:id]
    if @ssh_key.nil?
      flash[:alert] = "Unknown key"
    else
      @ssh_key.current_audit = Audit.create_from_object! @deployment, 'deleted', request.remote_ip, current_user
      @ssh_key.destroy
    end
    redirect_to "/deployments/#{@deployment.token}/ssh_keys"
  end

  private

  def ssh_key_params
    params.require(:deployment_ssh_key).permit(:pubkey)
  end

end
