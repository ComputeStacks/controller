class Admin::ContainerImagePluginsController < Admin::ApplicationController

  include RescueResponder

  before_action :find_products, only: %i[new edit update create]
  before_action :find_plugin, only: %i[show edit update destroy]

  def index
    @plugins = ContainerImagePlugin.all
  end

  def show; end

  def new
    @plugin = ContainerImagePlugin.new
  end

  def edit; end

  def create
    @plugin = ContainerImagePlugin.new plugin_params
    @plugin.current_user = current_user
    if @plugin.save
      redirect_to "/admin/container_image_plugins", notice: "#{@plugin.name} created"
    else
      render :new
    end
  end

  def update
    if @plugin.update plugin_params
      redirect_to "/admin/container_image_plugins", notice: "#{@plugin.name} updated"
    else
      render :edit
    end
  end

  def destroy
    if @plugin.save
      flash[:notice] = "#{@plugin.name} deleted"
    else
      flash[:alert] = @plugin.errors.full_messages.join(" ")
    end
    redirect_to "/admin/container_image_plugins"
  end

  private

  def find_plugin
    @plugin = ContainerImagePlugin.find params[:id]
    @plugin.current_user = current_user
  end

  def find_products
    @products = Product.addons.sorted
  end

  def plugin_params
    params.require(:container_image_plugin).permit(:name, :active, :is_optional, :product_id)
  end

  def not_found_responder
    redirect_to "/admin/container_image_plugins", alert: "Unknown Plugin"
  end

end
