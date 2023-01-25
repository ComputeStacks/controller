# Add and Remove plugins from an image
class Admin::ContainerImages::ImagePluginsController < Admin::ContainerImages::BaseController

  before_action :find_available_plugins, only: %i[new create]
  before_action :ensure_available_plugins, only: :new

  def index
    @plugins = ContainerImagePlugin.active
    render template: "container_images/image_plugins/index"
  end

  def new
    render template: "container_images/image_plugins/new"
  end

  def create
    cascade = params[:cascade_plugin].blank? ? false : true
    ImageWorkers::AddImagePluginWorker.perform_async current_user.id, @image.id, params[:add_plugin_id], cascade
    redirect_to "/admin/container_images/#{@image.id}", notice: "Plugin will be added shortly. Check System Alerts for any errors."
  end

  def destroy
    ImageWorkers::RemoveImagePluginWorker.perform_async current_user.id, @image.id, params[:id]
    redirect_to "/admin/container_images/#{@image.id}", notice: "Plugin will be removed shortly. Check System Alerts for any errors."
  end

  private

  def find_available_plugins
    @plugins = ContainerImagePlugin.active.select do |i|
      i.active && i.can_enable?(current_user) && !@image.container_image_plugins.include?(i)
    end
  end

  def ensure_available_plugins
    if @plugins.empty?
      redirect_to "/admin/container_images/#{@image.id}", alert: "There are no available plugins."
    end
  end

end
