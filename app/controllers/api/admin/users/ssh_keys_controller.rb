# User SSH Keys
class Api::Admin::Users::SshKeysController < Api::Admin::Users::BaseController

  before_action :find_key, only: %i[show destroy]

  # List all User SSH Keys
  #
  # `GET /api/admin/users/{user-id}/ssh_keys`
  #
  # * `user_ssh_keys`: Array
  #     * `id`: Integer
  #     * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def index
    @ssh_keys = paginate @user.ssh_keys.all
  end

  # View User SSH Keys
  #
  # `GET /api/admin/users/{user-id}/ssh_keys/{id}`
  #
  # * `user_ssh_key`: Object
  #     * `id`: Integer
  #     * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def show; end

  # Create User SSH Key
  #
  # `POST /api/admin/users/{user-id}/ssh_keys`
  #
  # * `user_ssh_key`: Object
  #     * `pubkey`: String - Public SSH Key

  def create
    @ssh_key = @user.ssh_keys.new ssh_key_params
    @ssh_key.current_audit = Audit.create_from_object! @user, 'updated', request.remote_ip, current_user
    @ssh_key.save
    return api_obj_error(@ssh_key.errors.full_messages) unless @ssh_key.errors.empty?
    render action: :show, status: :created
  end

  # Delete User SSH Key
  #
  # `DELETE /api/admin/users/{user-id}/ssh_keys/{id}
  # `
  def destroy
    @ssh_key.current_audit = Audit.create_from_object! current_user, 'deleted', request.remote_ip, current_user
    return api_obj_error(@ssh_key.errors.full_messages) unless @ssh_key.destroy
    render status: :accepted
  end

  private

  def ssh_key_params
    params.require(:user_ssh_key).permit(:pubkey)
  end

  def find_key
    @ssh_key = @user.ssh_keys.find params[:id]
  end

end
