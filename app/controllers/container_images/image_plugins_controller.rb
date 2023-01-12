# Add and Remove plugins from an image
class ContainerImages::ImagePluginsController < ContainerImages::BaseController

  before_action :find_available_plugins, only: %i[new create]
  before_action :ensure_available_plugins, only: :new
  before_action :authorize_action, only: %i[new create destroy]

  def index
    @plugins = ContainerImagePlugin.active
  end

  def new; end

  def create
    if @image.update add_plugin_id: params[:add_plugin_id]
      redirect_to "/container_images/#{@image.id}"
    else
      render :new
    end
  end

  def destroy
    plugin = @image.container_image_plugins.find_by id: params[:id]
    @image.container_image_plugins.delete plugin
    redirect_to "/container_images/#{@image.id}"
  end

  private

  def authorize_action
    unless current_user.is_admin
      redirect_to "/admin/container_images", alert: "permission denied"
      return false
    end
  end

  def find_available_plugins
    @plugins = ContainerImagePlugin.active.select do |i|
      i.available? && i.can_enable?(current_user) && !@image.container_image_plugins.include?(i)
    end
  end

  def ensure_available_plugins
    if @plugins.empty?
      redirect_to "/container_images/#{@image.id}", alert: "There are no available plugins."
    end
  end

end
