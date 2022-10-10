class Admin::ContainerImages::ImageVariantsController < Admin::ContainerImages::BaseController

  include RescueResponder

  before_action :find_variant, only: [:edit, :update, :destroy, :show]

  def index
    if request.xhr?
      render template: "container_images/image_variants/list", layout: false
    end
    render template: "container_images/image_variants/index"
  end

  def show
    if request.xhr?
      render template: "container_images/image_variants/validated_tag", layout: false
    end
  end

  def new
    @variant = @image.image_variants.new
    render template: "container_images/image_variants/new"
  end

  def edit
    render template: "container_images/image_variants/edit"
  end

  def create
    @variant = @image.image_variants.new variant_params

    if @variant.save
      redirect_to "/admin/container_images/#{@image.id}"
    else
      render template: "container_images/image_variants/new"
    end
  end

  def update
    if @variant.update variant_params
      redirect_to "/admin/container_images/#{@image.id}"
    else
      render template: "container_images/image_variants/edit"
    end
  end


  def destroy
    if @variant.destroy
      flash[:success] = "Variant removed"
    else
      flash[:alert] = "Error deleting variant: #{@variant.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/container_images/#{@image.id}"
  end

  private

  def find_variant
    @variant = @image.image_variants.find params[:id]
    @variant.current_user = current_user
  end

  def variant_params
    params.require(:container_image_image_variant).permit(
      :label,
      :registry_image_tag,
      :is_default,
      :registry_image_tag,
      :before_migrate,
      :after_migrate,
      :rollback_migrate
    )
  end

end
