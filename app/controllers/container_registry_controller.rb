class ContainerRegistryController < AuthController

  before_action :find_registry, only: %i[show edit update destroy]
  before_action :require_administer, only: :destroy

  def index
    @registries = ContainerRegistry.find_all_for current_user
    if request.xhr?
      render :template => "container_registry/registry_list", :layout => false
      return false
    end
  end

  def show; end

  def new
    @registry = ContainerRegistry.new
    @registry.current_user = current_user
  end

  def edit; end

  def update
    errors = []
    if params[:container_registry][:label].blank? || params[:container_registry][:label].nil?
      errors << "Missing Registry Name."
    end
    unless errors.empty?
      flash[:alert] = "Error! #{errors.join(' ')}"
      redirect_to "/container_registry/#{@registry.id}/edit"
      return false
    end
    if @registry.update(registry_params)
      redirect_to "/container_registry/#{@registry.id}", notice: t('container_registry.updated')
      return false
    end
    render template: 'container_registry/edit'
  end

  def create
    errors = []
    if params[:container_registry][:label].blank? || params[:container_registry][:label].nil?
      errors << "Missing Registry Name."
    end
    unless errors.empty?
      flash[:alert] = "Error! #{errors.join(' ')}"
      redirect_to "/container_registry/new"
      return false
    end
    @registry = ContainerRegistry.new(registry_params)
    @registry.user = current_user
    @registry.current_user = current_user
    if @registry.valid? && @registry.save
      RegistryWorkers::ProvisionRegistryWorker.perform_async @registry.id
      redirect_to "/container_registry", notice: t('container_registry.created')
      return false
    end
    render template: 'container_registry/new'
  end

  def destroy

    if @registry.destroy
      flash[:notice] = "Registry deleted"
    else
      flash[:alert] = "Error!: #{@registry.errors.full_messages.join(", ")}"
    end
    redirect_to "/container_registry"
  end

  private

  def registry_params
    params.require(:container_registry).permit(:label)
  end

  def find_registry
    @registry = ContainerRegistry.find_for current_user, { id: params[:id] }
    return redirect_to("/container_registry") if @registry.nil?
    @registry.current_user = current_user
  end

  def require_administer
    unless @registry.can_administer? current_user
      redirect_to "/container_registry/#{@registry.id}", alert: "Permission denied"
    end
  end

end
