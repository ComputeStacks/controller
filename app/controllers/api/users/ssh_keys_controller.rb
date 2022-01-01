##
# User SSH Keys
class Api::Users::SshKeysController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :profile_read }, only: %i[ index show ], unless: :current_user
  before_action -> { doorkeeper_authorize! :profile_update }, only: %i[ create destroy ], unless: :current_user

  before_action :find_key, only: %i[show destroy]

  ##
  # List all SSH Keys
  #
  # `GET /api/users/ssh_keys`
  #
  # **OAuth AuthorizationRequired**: `profile_read`
  #
  # * `ssh_keys`: Array
  #     * `id`: Integer
  #     * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @ssh_keys = current_user.ssh_keys
  end

  ##
  # View SSH Keys
  #
  # `GET /api/users/ssh_keys/{id}`
  #
  # **OAuth AuthorizationRequired**: `profile_read`
  #
  # * `ssh_key`: Object
  #     * `id`: Integer
  #     * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  ##
  # Create SSH Key
  #
  # `POST /api/users/ssh_keys`
  #
  # **OAuth AuthorizationRequired**: `profile_update`
  #
  # * `ssh_key`: Object
  #     * `pubkey`: String
  #
  def create
    @ssh_key = current_user.ssh_keys.new ssh_key_params
    @ssh_key.current_audit = Audit.create_from_object! current_user, 'updated', request.remote_ip, current_user
    @ssh_key.save
    return api_obj_error(@ssh_key.errors.full_messages) unless @ssh_key.errors.empty?
    render action: :show, status: :created
  end

  ##
  # Delete SSH Key
  #
  # `DELETE /api/users/ssh_keys/{id}`
  #
  # **OAuth AuthorizationRequired**: `profile_update`
  #
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
    @ssh_key = current_user.ssh_keys.find params[:id]
  end

end
