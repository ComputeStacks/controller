class ContainerImagesController < AuthController

  before_action :load_image, only: %i[show]
  before_action :load_protected_image, only: %i[edit update destroy]
  before_action :require_administer, only: :destroy

  def index
    @images = ContainerImage.find_all_for(current_user)
    # respond_to do |format|
    #   format.json {}
    #   format.html {}
    # end
  end

  def edit
    # @container.registry_password = @container.registry_secret&.decrypted
  end

  def update
    if @container.update(current_user.is_admin ? admin_container_params : container_params)
      redirect_to helpers.container_image_path(@container), notice: "Successfully updated container."
    else
      flash[:alert] = @container.errors.full_messages.join('. ')
      if params.dig(:container_image, :variant_pos)
        redirect_to "/container_images/#{@container.id}"
      else
        render template: 'container_images/edit'
      end
    end
  end

  def show
    if request.xhr?
      render template: 'container_images/show/tag_validator', layout: false
    end
  end

  def new
    @container = nil
    if new_container_params
      if new_container_params[:parent_image_id]
        @parent_image = ContainerImage.find_by("id = ? AND (user_id is null OR user_id = ?)", new_container_params[:parent_image_id], current_user.id)
        if @parent_image
          @container = @parent_image.dup
          @container.registry_image_tag = @parent_image.default_variant.registry_image_tag
          @container.parent_image_id = @parent_image.id
          @container.user = current_user
          @container.current_user = current_user
          @container.registry_password = nil
          @container.registry_username = nil
        end
      end
      if new_container_params[:container_image_provider_id]
        provider = helpers.available_image_providers.find_by(id: new_container_params[:container_image_provider_id])
        unless provider.nil? # Gracefully fail if we can't find it
          @container = current_user.container_images.new(new_container_params)
          @container.current_user = current_user
          @container.can_scale = true
          @container.enable_sftp = true
        end
      end
    end

    @container = current_user.container_images.new(
      current_user: current_user,
      registry_image_tag: "latest",
      can_scale: true,
      container_image_provider: ContainerImageProvider.find_default&.first,
    ) unless @container
  end

  def create
    @container = current_user.container_images.new(current_user.is_admin ? admin_container_params : container_params)
    @container.current_user = current_user

    if @container.save
      redirect_to helpers.container_image_path(@container)
    else
      render template: 'container_images/new'
    end
  end

  def destroy
    if @container.destroy
      flash[:notice] = "Successfully deleted image."
    else
      flash[:alert] = @container.errors.full_messages.join('. ')
    end
    redirect_to "/container_images"
  end

  private

  # For CRUD operations
  def load_image
    @container = ContainerImage.find_for current_user, id: params[:id]
    if @container.nil?
      redirect_to "/container_images", alert: "Unknown Image."
      return false
    end
    @container.current_user = current_user
  end

  def load_protected_image
    @container = ContainerImage.find_for_edit current_user, id: params[:id]
    if @container.nil?
      redirect_to "/container_images", alert: "Unknown Image."
      return false
    end
    @container.current_user = current_user
  end

  def container_params
    params.require(:container_image).permit(
      :label, :description, :command, :role, :category, :can_scale, :active, :enable_sftp,
      :parent_image_id, :registry_username, :registry_password, :registry_custom, :registry_image_path,
      :registry_image_tag, :registry_auth, :container_image_provider_id, :min_cpu, :min_memory, :tag_list,
      :force_local_volume, variant_pos: []
    )
  end

  def admin_container_params
    params.require(:container_image).permit(
      :label, :description, :command, :role, :category, :can_scale, :active, :enable_sftp,
      :parent_image_id, :registry_username, :registry_password, :registry_custom, :registry_image_path,
      :registry_image_tag, :registry_auth, :container_image_provider_id, :min_cpu, :min_memory, :tag_list,
      :force_local_volume, :override_autoremove, :is_free, variant_pos: []
    )
  end

  def new_container_params
    params.require(:container_image).permit(:container_image_provider_id, :registry_image_path, :registry_image_tag, :parent_image_id, :tag_list, :force_local_volume)
  rescue ActionController::ParameterMissing
    nil
  end

  def require_administer
    unless @container.can_administer? current_user
      redirect_to "/container_images/#{@container.id}", alert: "Permission denied"
    end
  end

end
