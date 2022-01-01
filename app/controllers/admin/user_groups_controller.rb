class Admin::UserGroupsController < Admin::ApplicationController

  before_action :find_group, only: %w(show edit update destroy)
  before_action :load_locations, only: %w(new edit update create destroy)

  def index
    @groups = UserGroup.all
  end

  def show
    redirect_to "/admin/user_groups/#{@group.id}/edit"
  end

  def edit; end

  def new
    if params[:clone]
      parent_group = UserGroup.find_by(id: params[:clone])
      @group = parent_group.dup
      @group.name = "#{parent_group.name}-#{SecureRandom.hex(2)}"
      @group.regions = parent_group.regions
      @group.is_default = false
    else
      @group = UserGroup.new
    end
  end

  def update
    if @group.update(group_params)
      redirect_to "/admin/user_groups"
    else
      render template: 'admin/user_groups/edit'
    end
  end

  def create
    @group = UserGroup.new(group_params)
    @group.current_user = current_user
    if @group.save
      redirect_to "/admin/user_groups"
    else
      render template: 'admin/user_groups/new'
    end
  end

  def destroy
    if @group.is_default
      redirect_to "/admin/user_groups", alert: "Error! Please choose a new default group before deleting this one."
      return false
    end
    if @group.destroy
      redirect_to "/admin/user_groups"
    else
      redirect_to "/admin/user_groups", alert: @group.errors.full_messages.join(' ')
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

  def find_group
    @group = UserGroup.find_by(id: params[:id])
    if @group.nil?
      redirect_to "/admin/user_groups", alert: 'Unknown Group'
      return false
    end
    @group.current_user = current_user
  end

  def load_locations
    @locations = Location.sorted
  end

end
