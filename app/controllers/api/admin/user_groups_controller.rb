##
# User Groups
class Api::Admin::UserGroupsController < Api::Admin::ApplicationController

  before_action :load_user_group, except: %i[ index create ]

  ##
  # List All User Groups
  #
  # `GET /api/admin/user_groups`
  #
  # * `user_groups`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `is_default`: Boolean
  #     * `billing_plan_id`: Integer
  #     * `active`: Boolean
  #     * `q_containers`: Integer
  #     * `q_dns_zones`: Integer
  #     * `q_cr`: Integer
  #     * `allow_local_volume`: Boolean - When using NFS volume storage, enable this to allow users to choose.
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `bill_offline`: Boolean - Continue billing containers when they're stopped. Volumes and backups are always billed. (default: true)
  #     * `bill_suspended`: Boolean - Continue billing suspended users. (default: true)
  #     * `remove_stopped`: Boolean - Remove stopped containers from the node. Persistent volumes will remain. When the user starts the container, it will be repovisioned automatically. (default: false)
  def index
    @groups = paginate UserGroup.all.sorted
    respond_to :json, :xml
  end

  ##
  # View User Group
  #
  # `GET /api/admin/user_groups/{id}`
  #
  # * `user_group`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `is_default`: Boolean
  #     * `billing_plan_id`: Integer
  #     * `active`: Boolean
  #     * `q_containers`: Integer
  #     * `q_dns_zones`: Integer
  #     * `q_cr`: Integer
  #     * `allow_local_volume`: Boolean - When using NFS volume storage, enable this to allow users to choose.
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `bill_offline`: Boolean - Continue billing containers when they're stopped. Volumes and backups are always billed. (default: true)
  #     * `bill_suspended`: Boolean - Continue billing suspended users. (default: true)
  #     * `remove_stopped`: Boolean - Remove stopped containers from the node. Persistent volumes will remain. When the user starts the container, it will be repovisioned automatically. (default: false)
  def show
    respond_to :json, :xml
  end

  ##
  # Edit User Group
  #
  # `PATCH /api/admin/user_groups/{id}`
  #
  # * `user_group`: Object
  #     * `name`: String
  #     * `is_default`: Boolean
  #     * `billing_plan_id`: Integer
  #     * `active`: Boolean
  #     * `q_containers`: Integer
  #     * `q_dns_zones`: Integer
  #     * `q_cr`: Integer
  #     * `allow_local_volume`: Boolean - When using NFS volume storage, enable this to allow users to choose.
  #     * `bill_offline`: Boolean - Continue billing containers when they're stopped. Volumes and backups are always billed. (default: true)
  #     * `bill_suspended`: Boolean - Continue billing suspended users. (default: true)
  #     * `remove_stopped`: Boolean - Remove stopped containers from the node. Persistent volumes will remain. When the user starts the container, it will be repovisioned automatically. (default: false)
  def update
    return api_obj_error(@group.errors.full_messages) unless @group.update(group_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create User Group
  #
  # `POST /api/admin/user_groups`
  #
  # * `user_group`: Object
  #     * `name`: String
  #     * `is_default`: Boolean
  #     * `billing_plan_id`: Integer
  #     * `active`: Boolean
  #     * `q_containers`: Integer
  #     * `q_dns_zones`: Integer
  #     * `q_cr`: Integer
  #     * `allow_local_volume`: Boolean - When using NFS volume storage, enable this to allow users to choose.
  #     * `bill_offline`: Boolean - Continue billing containers when they're stopped. Volumes and backups are always billed. (default: true)
  #     * `bill_suspended`: Boolean - Continue billing suspended users. (default: true)
  #     * `remove_stopped`: Boolean - Remove stopped containers from the node. Persistent volumes will remain. When the user starts the container, it will be repovisioned automatically. (default: false)

  def create
    @group = UserGroup.new(group_params)
    @group.current_user = current_user
    return api_obj_error(@group.errors.full_messages) unless @group.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Delete User Group
  #
  # `DELETE /api/admin/user_groups/{id}`
  #
  # You must first remove any users from this group before deleting it

  def destroy
    return api_obj_error(@group.errors.full_messages) unless @group.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  def group_params
    params.require(:user_group).permit(
      :name, :is_default, :billing_plan_id, :q_containers,
      :allow_local_volume, :q_cr, :q_images, :bill_offline,
      :bill_suspended, :remove_stopped, { region_ids: [] }
    )
  end

  def load_user_group
    @group = UserGroup.find_by(id: params[:id])
    return api_obj_missing if @group.nil?
    @group.current_user = current_user
  end

end
