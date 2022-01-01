class Users::SshKeysController < AuthController

  def index
    @ssh_keys = current_user.ssh_keys
  end

  def new
    @ssh_key = current_user.ssh_keys.new
  end

  def create
    @ssh_key = current_user.ssh_keys.new ssh_key_params
    @ssh_key.current_audit = Audit.create_from_object! current_user, 'updated', request.remote_ip, current_user
    if @ssh_key.save
      redirect_to "/users/ssh_keys"
    else
      render action: :new
    end
  end

  def destroy
    @ssh_key = current_user.ssh_keys.find_by id: params[:id]
    if @ssh_key.nil?
      flash[:alert] = "Unknown key"
    else
      @ssh_key.current_audit = Audit.create_from_object! current_user, 'deleted', request.remote_ip, current_user
      @ssh_key.destroy
    end
    redirect_to "/users/ssh_keys"
  end

  private

  def ssh_key_params
    params.require(:user_ssh_key).permit(:pubkey)
  end

end
