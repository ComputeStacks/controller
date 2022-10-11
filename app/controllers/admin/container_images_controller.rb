class Admin::ContainerImagesController < Admin::ApplicationController

  before_action :load_container, only: [:edit, :update, :destroy, :show]
  before_action :load_blocks, only: %w(new edit update create)

  def index
    containers = ContainerImage
    containers = case params[:user].to_i
    when 0
      containers
    else
      @user = User.find_by(id: params[:user])
      @user.nil? ? containers : @user.container_images
    end

    containers = case params[:state]
    when 'public'
      containers.where(user: nil)
    when 'private'
      containers.where.not(user: nil)
    else
      containers
    end

    containers = case params[:kind]
    when 'containers'
      containers.where(is_load_balancer: false)
    when 'loadbalancers'
      containers.where(is_load_balancer: true)
    else
      containers
    end

    containers = case params[:visible]
    when 'yes'
      containers.where(active: true)
    when 'no'
      containers.where(active: false)
    else
      containers
    end

    @containers = containers.sorted.paginate page: params[:page], per_page: 30
  end

  def edit; end

  def update
    if @container.update(container_params)
      redirect_to helpers.container_image_path(@container), success: "Successfully updated container."
    else
      flash[:alert] = @container.errors.full_messages.join('. ')
      if params.dig(:container_image, :variant_pos)
        redirect_to helpers.container_image_path(@container)
      else
        render template: 'admin/container_images/edit'
      end
    end
  end

  def show
    if request.xhr?
      render template: 'container_images/show/tag_validator', layout: false
    else
      render template: "container_images/show"
    end
  end

  def new

    @container = nil
    if new_container_params
      if new_container_params[:parent_image_id]
        @parent_image = ContainerImage.find_by("id = ? AND (user_id is null OR user_id = ?)", new_container_params[:parent_image_id], current_user.id)
        if @parent_image
          @container = @parent_image.dup
          @container.parent_image_id = @parent_image.id

          # Admins have the ability to create public images, so only set this if we're cloning a private image.
          @container.user = @parent_image.user.nil? ? nil : current_user

          @container.current_user = current_user
          @container.registry_password = nil
          @container.registry_username = nil
        end
      end

      if new_container_params[:container_image_provider_id]
        provider = ContainerImageProvider.find_by(id: new_container_params[:container_image_provider_id])
        unless provider.nil? # Gracefully fail if we can't find it
          @container = ContainerImage.new(new_container_params)
          @container.user = provider.user.nil? ? nil : provider.user
          @container.current_user = current_user
          @container.can_scale = true
        end
      end
    end

    @container = current_user.container_images.new(
      current_user: current_user,
      can_scale: true,
      container_image_provider: ContainerImageProvider.find_default&.first,
      ) unless @container

  end

  def create
    @container = ContainerImage.new(container_params)
    @container.current_user = current_user

    if @container.save
      redirect_to helpers.container_image_path(@container), success: "Successfully created image"
    else
      render template: 'admin/container_images/new'
    end
  end

  def destroy
    if @container.destroy
      flash[:notice] = "Successfully deleted image."
    else
      flash[:alert] = @container.errors.full_messages.join('. ')
    end
    redirect_to "/admin/container_images"
  end

  private

  def load_container
    @container = ContainerImage.find_by(id: params[:id])
    if @container.nil?
      redirect_to "/admin/container_images", alert: "Unknown Container."
      return false
    end
    @container.current_user = current_user
  end

  def container_params
    params.require(:container_image).permit(
      :label, :description, :role, :category, :can_scale, :active, :command,
      :parent_image_id, :registry_username, :registry_password, :registry_custom, :registry_image_path,
      :registry_image_tag, :registry_auth, :container_image_provider_id, :min_cpu, :min_memory, :user_id,
      :general_block_id, :remote_block_id, :domains_block_id, :ssh_block_id, :tag_list, :is_load_balancer,
      :is_free, :force_local_volume, :override_autoremove, variant_pos: []
    )
  end

  def new_container_params
    params.require(:container_image).permit(:container_image_provider_id, :registry_image_path, :registry_image_tag, :parent_image_id, :tag_list, :is_load_balancer, :is_free, :force_local_volume)
  rescue ActionController::ParameterMissing
    nil
  end

  def load_blocks
    @custom_blocks = Block.where("content_key is null OR content_key = ''").joins(:block_contents).distinct
  end

end
