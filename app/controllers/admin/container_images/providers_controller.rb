class Admin::ContainerImages::ProvidersController < Admin::ApplicationController

  before_action :find_provider, only: %i[show edit update destroy]

  def index
    @providers = ContainerImageProvider.sorted.paginate page: params[:page], per_page: 30
  end

  def show
    redirect_to admin_container_images_providers_url
  end

  def new
    @provider = ContainerImageProvider.new
    @provider.current_user = current_user
    @provider.is_default = false
  end

  def edit; end

  def update
    if provider_params.empty?
      redirect_to admin_container_images_provider_url(@provider), notice: "Nothing was changed."
    else
      if @provider.update(provider_params)
        redirect_to admin_container_images_provider_url(@provider), success: "Successfully updated provider."
      else
        render template: "admin/container_images/providers/edit"
      end
    end
  end

  def create
    @provider = ContainerImageProvider.new(provider_params)
    @provider.current_user = current_user
    if @provider.save
      redirect_to admin_container_images_provider_url(@provider), success: "Successfully created provider."
    else
      render template: "admin/container_images/providers/new"
    end
  end

  def destroy
    if @provider.destroy
      flash[:success] = "Successfully deleted provider."
    else
      flash[:alert] = @provider.errors.full_messages.join('. ')
    end
    redirect_to admin_container_images_providers_url
  end

  private

  def find_provider
    @provider = ContainerImageProvider.find_by(id: params[:id])
    if @provider.nil?
      redirect_to "/admin/container_images/providers", alert: "Unknown provider"
      return false
    end
    @provider.current_user = current_user
  end

  def provider_params
    params.require(:container_image_provider).permit(:name, :hostname, :is_default, :container_registry_id)
  rescue
    []
  end

end
