class Admin::ContainerRegistryController < Admin::ApplicationController

  before_action :find_registry, only: %i[show edit update destroy]

  def index
    @registries = ContainerRegistry.all.paginate page: params[:page], per_page: 30
  end

  def show; end

  def new
    @registry = ContainerRegistry.new
    @registry.current_user = current_user
  end

  def edit; end

  def update
    if @registry.update(registry_params)
      redirect_to "/admin/container_registry/#{@registry.id}", notice: t('container_registry.updated')
    else
      render action: :edit
    end
  end

  def create
    @registry = ContainerRegistry.new(registry_params)
    @registry.current_user = current_user
    if @registry.save
      @registry.delay(retry: false).deploy!
      redirect_to "/admin/container_registry/#{@registry.id}", success: t('container_registry.created')
    else
      render action: :new
    end
  end

  def destroy
    if @registry.destroy
      flash[:notice] = "Registry deleted"
    else
      flash[:alert] = "Error!: #{@registry.errors.full_messages.join(", ")}"
    end
    redirect_to "/admin/container_registry"
  end

  private

  def find_registry
    @registry = ContainerRegistry.find_by(id: params[:id])
    if @registry.nil?
      return redirect_to("/admin/container_registry", alert: "Unknown registry")
    end
    @registry.current_user = current_user
  end

  def registry_params
    params.require(:container_registry).permit(:label, :user_id)
  end

end
